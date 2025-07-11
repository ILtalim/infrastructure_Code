# lambda/upload_handler.py
import os
import json
import boto3

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))  # 👈 Log the incoming event

    ddb_table = os.environ['DDB_TABLE_NAME']
    sns_arn = os.environ['SNS_TOPIC_ARN']
    
    
    s3_event = event['Records'][0]['s3']
    bucket = s3_event['bucket']['name']
    key = s3_event['object']['key']

    print(f"Bucket: {bucket}, Key: {key}")  # 👈 Log bucket and key

    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(ddb_table)
    
    # Save metadata to DynamoDB
    table.put_item(Item={
        'document_id': key,
        'bucket': bucket
    })

    print("DynamoDB put_item response:", response)  # 👈 Log response

    sns = boto3.client('sns')
    sns.publish(
        TopicArn=sns_arn,
        Subject='New Document Uploaded',
        Message=f'Document uploaded: {key} in bucket {bucket}'
    )

    print("SNS publish response:", sns_response)  # 👈 Log SNS response

    return {
        'statusCode': 200,
        'body': json.dumps('Success')
    }
