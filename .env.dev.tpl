# Postgres credentials 
POSTGRES_DB=amj_doc_db
POSTGRES_USER=amj_doc_db_user
POSTGRES_PASSWORD=m3_f1le_7!
POSTGRES_HOST=postgres-db
POSTGRES_PORT=5432

# AWS credentials and region
AWS_ACCESS_KEY_ID=AKIA2OLJJABVYOO4SNF6
AWS_SECRET_ACCESS_KEY=your-SgpI95XgG2g7qvG0zjUpBnG4f0hggnDzi+Me93hq
AWS_DEFAULT_REGION=us-east-1
# S3 Bucket
AWS_S3_BUCKET=${AWS_S3_BUCKET}
# DynamoDB
AWS_DYNAMODB_TABLE_NAME=${AWS_DYNAMODB_TABLE_NAME}
# CDN
AWS_CDN_BASE_URL=${AWS_CDN_BASE_URL}
# API Gateway
# AWS_API_GATEWAY_REST_API_ID=${AWS_API_GATEWAY_REST_API_ID}
AWS_API_GATEWAY_REST_API_ID=gc0n9zkxme
AWS_API_GATEWAY_STAGE_NAME=dev

# CELERY
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/0

# AIFastAPI env settings
PINECONE_API_KEY=pcsk_4NZXbf_KbJpQYWg9WmMHyRwf1hgofMsXYoLnBinMHTeLymiNJCkrsiEQk3X1NNCRPxGV3F
PINECONE_ENV=aws-tl

EMBEDDING_MODEL=intfloat/e5-base-v2 #intfloat/e5-large-v2 
GENERATIVE_MODEL=google/flan-t5-base #google/flan-t5-xl 
PINECONE_INDEX=doc-embeddings

PDF_FOLDER="./docs/sample_memo.pdf"
GENERATE_RESPONSES=false

NEO4J_BOLT_URL=bolt://neo4j:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=strongpass123

# Frontend environment variables
# These variables are used in the Next.js frontend application
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_83qffpg6P    
NEXT_PUBLIC_COGNITO_CLIENT_ID=4fr7oh7rqqlbqpki85e19k11u6  
NEXT_PUBLIC_API_BASE_URL=https://prodtest.ailawal.ca