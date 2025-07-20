import os
import json
import boto3
import base64
import requests
from urllib.parse import unquote_plus
from datetime import datetime, timedelta
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend

# Initialize AWS clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
secrets_client = boto3.client("secretsmanager")

# Environment variables (set in Terraform)
CF_KEY_PAIR_ID = os.environ['CF_KEY_PAIR_ID']
CF_CDN_DOMAIN = os.environ['CF_CDN_DOMAIN']
DJANGO_CALLBACK_URL = os.environ['DJANGO_CALLBACK_URL']
DDB_TABLE_NAME = os.environ['DDB_TABLE_NAME']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
PRIVATE_KEY_SECRET_NAME = os.environ['PRIVATE_KEY_SECRET_NAME']

# Initialize DynamoDB table
table = dynamodb.Table(DDB_TABLE_NAME)

def get_private_key():
    """Retrieve the CloudFront private key from AWS Secrets Manager"""
    try:
        secret_value = secrets_client.get_secret_value(SecretId=PRIVATE_KEY_SECRET_NAME)
        return secret_value["SecretString"]
    except Exception as e:
        print(f"Error retrieving private key: {e}")
        raise

PRIVATE_KEY_PEM = get_private_key()

def generate_signed_url(url, expire_minutes=30):
    """Generate a CloudFront signed URL"""
    expire_time = int((datetime.utcnow() + timedelta(minutes=expire_minutes)).timestamp())
    policy_dict = {
        "Statement": [
            {
                "Resource": url,
                "Condition": {
                    "DateLessThan": {
                        "AWS:EpochTime": expire_time
                    }
                }
            }
        ]
    }
    policy = json.dumps(policy_dict)

    try:
        private_key = serialization.load_pem_private_key(
            PRIVATE_KEY_PEM.encode(), 
            password=None, 
            backend=default_backend()
        )
        signature = private_key.sign(
            policy.encode(), 
            padding.PKCS1v15(), 
            hashes.SHA1()
        )
        encoded_signature = base64.b64encode(signature).decode().replace('+','-').replace('=','_').replace('/','~')

        return f"{url}?Expires={expire_time}&Signature={encoded_signature}&Key-Pair-Id={CF_KEY_PAIR_ID}"
    except Exception as e:
        print(f"Error generating signed URL: {e}")
        raise

def process_record(record):
    """Process a single S3 event record"""
    bucket = record['s3']['bucket']['name']
    key = unquote_plus(record['s3']['object']['key'])
    
    # Generate required values
    s3_uri = f"s3://{bucket}/{key}"
    file_hash = key.split('/')[-1].replace('.pdf', '')
    cloudfront_url = f"https://{CF_CDN_DOMAIN}/{key}"
    signed_url = generate_signed_url(cloudfront_url)

    # Store in DynamoDB
    try:
        table.put_item(
            Item={
                'document_id': file_hash,
                's3_uri': s3_uri,
                'cloudfront_url': cloudfront_url,
                'signed_url': signed_url,
                'status': 'PROCESSING',
                'timestamp': datetime.utcnow().isoformat()
            }
        )
    except Exception as e:
        print(f"Error writing to DynamoDB: {e}")
        raise

    # Send notification
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=f"New document uploaded: {s3_uri}",
            Subject="New Document Upload"
        )
    except Exception as e:
        print(f"Error sending SNS notification: {e}")

    # Send to Django backend
    payload = {
        "file_hash": file_hash,
        "s3_uri": s3_uri,
        "cdn_url": signed_url
    }

    print(f"📤 Posting to Django: {DJANGO_CALLBACK_URL}")
    try:
        res = requests.post(DJANGO_CALLBACK_URL, json=payload, timeout=10)
        res.raise_for_status()
        print(f"✅ Status: {res.status_code}, Response: {res.text}")
        
        # Update status in DynamoDB if successful
        table.update_item(
            Key={'document_id': file_hash},
            UpdateExpression="set #status = :s",
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':s': 'PROCESSED'}
        )
    except Exception as e:
        print(f"❌ Error calling Django: {e}")
        table.update_item(
            Key={'document_id': file_hash},
            UpdateExpression="set #status = :s",
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':s': 'ERROR'}
        )
        raise

def lambda_handler(event, context):
    """Main Lambda handler function"""
    try:
        for record in event.get('Records', []):
            process_record(record)
        
        return {
            "statusCode": 200,
            "body": json.dumps({"status": "success"})
        }
    except Exception as e:
        print(f"❌ Lambda execution error: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"status": "error", "message": str(e)})
        }