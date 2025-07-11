# #!/bin/bash
# yum update -y
# # Install Amazon SSM Agent - Note: ${region} should be passed via templatefile in Terraform
# dnf install -y https://s3."${region}".amazonaws.com/amazon-ssm-"${region}"/latest/linux_amd64/amazon-ssm-agent.rpm
# curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
# yum install -y session-manager-plugin.rpm
# yum install wget -y
# yum install maven -y
# yum install git pip unzip -y
# # Installing awscli
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
# unzip awscliv2.zip
# sudo ./aws/install
# sudo ln -svf /usr/local/bin/aws /usr/bin/aws
# # Install Jenkins
# wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
# rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
# yum upgrade -y
# yum install java-17-openjdk -y
# yum install jenkins -y
# sed -i 's/^User=jenkins/User=root/' /usr/lib/systemd/system/jenkins.service
# systemctl daemon-reload
# systemctl start jenkins
# systemctl enable jenkins
# systemctl start jenkins
# # Install trivy for container scanning
# RELEASE_VERSION=$(grep -Po '(?<=VERSION_ID=")[0-9]' /etc/os-release)
# cat << EOT | sudo tee -a /etc/yum.repos.d/trivy.repo
# [trivy]
# name=Trivy repository
# baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$RELEASE_VERSION/\$basearch/
# gpgcheck=0
# enabled=1
# EOT
# yum -y update
# yum -y install trivy
# # Install Docker
# curl -fsSL https://get.docker.com -o get-docker.sh
# sudo sh get-docker.sh
# rm get-docker.sh

# # Add user 'ubuntu' to docker group
# sudo usermod -aG docker ubuntu

# # Start and enable Docker service
# echo "Docker installed and user added to docker group."
# echo "Starting Docker service..."
# sudo systemctl start docker
# sudo systemctl enable docker
# echo "Docker service started and enabled to start on boot."

# # Install Docker Compose plugin (v2)
# sudo apt-get update
# sudo apt-get install -y docker-compose-plugin

# # Verify installation
# docker compose version

# echo "Docker service started and enabled to start on boot."
# hostnamectl set-hostname jenkins-server

#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g. with sudo). Exiting."
  exit 1
fi

echo "=== Updating system packages ==="
# Update system packages
apt-get update
apt-get upgrade -y

echo "=== Installing core utilities (curl, wget, unzip, etc.) ==="
# Install core utilities: curl, wget, unzip, git, etc.
apt-get install -y curl wget unzip maven git python3-pip software-properties-common apt-transport-https ca-certificates gnupg lsb-release

echo "=== Installing AWS SSM Agent via snap ==="
# Install AWS SSM Agent via snap
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

echo "=== Installing AWS Session Manager plugin ==="
# Install AWS Session Manager plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
apt-get install -y ./session-manager-plugin.deb
rm -f session-manager-plugin.deb

echo "=== Installing AWS CLI version 2 ==="
# Install AWS CLI version 2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws
ln -sf /usr/local/bin/aws /usr/bin/aws

echo "=== Adding Jenkins repository key and source list ==="
# Add Jenkins repository key and source list
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

echo "=== Updating packages and installing OpenJDK 17 and Jenkins ==="
# Update packages and install OpenJDK 17 and Jenkins
apt-get update
apt-get install -y openjdk-17-jdk jenkins

echo "=== Enabling and starting Jenkins service ==="
# Enable and start Jenkins service
systemctl enable jenkins
systemctl start jenkins

echo "=== Installing Docker ==="
# Install Docker using official convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm -f get-docker.sh

echo "=== Adding ubuntu user to docker group (requires logout/login) ==="
# Add ubuntu user to docker group (requires logout/login to take effect)
usermod -aG docker ubuntu

echo "=== Enabling and starting Docker service ==="
# Enable and start Docker service
systemctl enable docker
systemctl start docker

echo "=== Installing Docker Compose plugin ==="
# Install Docker Compose plugin
apt-get update
apt-get install -y docker-compose-plugin

echo "=== Verifying Docker Compose installation ==="
# Verify Docker Compose installation
docker compose version

echo "=== Installing Trivy security scanner ==="
# Install Trivy security scanner
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/trivy.list
apt-get update
apt-get install -y trivy

echo "=== Setting hostname to jenkins-server ==="
# Set hostname of the machine
hostnamectl set-hostname jenkins-server

echo "=== Setup completed successfully ==="
