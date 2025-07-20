#!/bin/bash

set -e
echo "🔄 Updating system and installing required packages..."
apt-get update
apt-get install -y curl unzip jq git

# Installing awscli
echo "🧰 Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sudo ln -svf /usr/local/bin/aws /usr/bin/aws
# Add Docker's official GPG key:
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user
echo "Docker installation and test completed successfully."
# installing Docker Compose
echo "🛠️ Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
echo "Docker Compose installed."
# Installing Nginx
echo "🌐 Installing Nginx..."
systemctl start nginx
systemctl enable nginx

# Create application directory
echo "📁 Preparing application directory..."
mkdir -p /opt/app && cd /opt/app
# pull .env files from AWS secret manager
echo "🔐 Fetching environment variables from AWS Secrets Manager..."
aws secretsmanager get-secret-value \
  --secret-id env/dev \
  --query SecretString \
  --output text > .env.dev

# aws secretsmanager get-secret-value \
#   --secret-id env/celery-pinecone \
#   --query SecretString \
#   --output text > .env.celery_pinecone



# Download docker-compose.yml from private GitHub repo (authenticated)
echo "📦 Downloading docker-compose.yml from private GitHub repo..."
if [ -z "$PAT_TOKEN" ]; then
  echo "❌ GITHUB_PAT_TOKEN environment variable is not set."
  exit 1
fi

curl -H "Authorization: token ${{ secrets.PAT_TOKEN }}" \
     -H "Accept: application/vnd.github.v3.raw" \
     -o docker-compose.yml \
     https://api.github.com/repos/ILtalim/airflowCode/contents/docker-compose.yml?ref=main


# Login to Docker Hub
echo "🔐 Logging into Docker Hub..."
# Securely store credentials using SSM or Secrets Manager; don't hardcode
DOCKER_USER="Consultlawal"
DOCKER_PASSWORD=$(aws secretsmanager get-secret-value --secret-id docker/credentials --query SecretString --output text | jq -r '.DOCKER_PASSWORD')

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USER" --password-stdin

echo "🚀 Starting app with Docker Compose..."
docker-compose pull
docker-compose up -d

echo "✅ Deployment complete!"