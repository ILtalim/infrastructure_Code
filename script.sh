#!/bin/bash
apt-get update
apt-get install -y curl unzip jq git
# Installing awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sudo ln -svf /usr/local/bin/aws /usr/bin/aws
# Add Docker's official GPG key:
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
systemctl start docker
systemctl enable docker
echo "Docker installation and test completed successfully."
# installing Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo "Docker Compose installed successfully."
mkdir -p /opt/app && cd /opt/app
# pull .env files from AWS secret manager
aws secretsmanager get-secret-value \
  --secret-id env/dev \
  --query SecretString \
  --output text > .env

# Download docker-compose.yml from private GitHub repo (authenticated)
curl -H "Authorization: token ${{ secrets.PAT_TOKEN }}" \
     -H "Accept: application/vnd.github.v3.raw" \
     -o docker-compose.yml \
     https://api.github.com/repos/eamanze/project-1/contents/docker-compose.yml


# Login to Docker Hub
docker login --username eamanze --password-stdin <<EOF
&KX#+k!M2jqhGFv
EOF
# echo "$pass" | docker login -u "$user" --password-stdin
cd /opt/app && docker-compose pull && docker-compose up -d