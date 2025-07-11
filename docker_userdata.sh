# #!/bin/bash
# apt-get update -y

# # Install AWS SSM agent
# if ! systemctl status amazon-ssm-agent; then
#   snap install amazon-ssm-agent --classic || \
#   apt-get install -y amazon-ssm-agent
# fi

# systemctl enable amazon-ssm-agent
# systemctl start amazon-ssm-agent

# # install AWS CLI v2
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
# sudo apt-get install -y unzip
# unzip awscliv2.zip
# sudo ./aws/install
# aws --version


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
# sudo apt  install docker-compose -y

# # Verify installation
# docker compose version

# hostnamectl set-hostname prodtest-server

# # ======== Resize root EBS volume filesystem to use full size ========
# # Install cloud-utils-growpart if missing
# apt-get install -y cloud-guest-utils

# systemctl start nginx
# systemctl enable nginx

# # Extend partition
# growpart /dev/xvda 1

# # Detect filesystem type and resize appropriately
# FS_TYPE=$(lsblk -f /dev/xvda1 | awk 'NR==2 {print $2}')

# if [ "$FS_TYPE" = "xfs" ]; then
#   xfs_growfs /
# elif [ "$FS_TYPE" = "ext4" ]; then
#   resize2fs /dev/xvda1
# else
#   echo "Unsupported filesystem type: $FS_TYPE"
#   exit 1
# fi

# # Optional: format and mount additional volume if attached (e.g. /dev/nvme1n1)
# if lsblk | grep -q "nvme1n1"; then
#   mkfs.ext4 /dev/nvme1n1
#   mkdir -p /mnt/data
#   mount /dev/nvme1n1 /mnt/data
#   echo '/dev/nvme1n1 /mnt/data ext4 defaults,nofail 0 2' >> /etc/fstab
# fi

# # Create app directory on mounted volume
# mkdir -p /mnt/data/apps

# # Move your app files if they exist (assuming previously placed in /root/test/)
# if [ -d "/root/test" ]; then
#   mv /root/test/* /mnt/data/apps/
#   chmod -R 775 /mnt/data/apps/
# fi

# # If docker-compose.yml exists, start services
# if [ -f /mnt/data/apps/docker-compose.yml ]; then
#   cd /mnt/data/apps
#   docker compose up -d || docker-compose up -d
# fi

# # Done: optional restart services
# systemctl restart docker
# systemctl restart nginx

# echo "Root filesystem resized."

# echo "Setup completed successfully."


#!/bin/bash
set -xe

# Ensure network is up before continuing
sleep 10

# Update packages
sudo apt-get update -y

# Install required tools
sudo apt-get install -y unzip cloud-guest-utils jq

# Install AWS SSM agent
if ! systemctl status amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic || sudo apt-get install -y amazon-ssm-agent
fi
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

# Install AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Add user to docker group
sudo usermod -aG docker ubuntu

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# install niginx
sudo apt update && sudo apt install -y nginx
# Install Docker Compose
sudo apt-get install -y docker-compose-plugin docker-compose

# --- Set Hostname ---
hostnamectl set-hostname prodtest-server

# Wait for secondary EBS device
DEVICE="/dev/nvme1n1"
MOUNT_POINT="/mnt/data"

for i in {1..10}; do
  if [ -b "$DEVICE" ]; then
    break
  fi
  echo "Waiting for $DEVICE to appear..."
  sleep 5
done

# Format disk if not already formatted
if ! file -s $DEVICE | grep -q ext4; then
  sudo mkfs.ext4 $DEVICE
fi

# Mount the volume
sudo mkdir -p $MOUNT_POINT
sudo mount $DEVICE $MOUNT_POINT
grep -q "$DEVICE" /etc/fstab || echo "$DEVICE $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Create required directories
sudo mkdir -p $MOUNT_POINT/apps
sudo mkdir -p $MOUNT_POINT/docker
sudo chmod 775 $MOUNT_POINT/apps $MOUNT_POINT/docker

# Move Docker data directory
sudo systemctl stop docker
if [ ! -L /var/lib/docker ]; then
  sudo mv /var/lib/docker /var/lib/docker.bak
  sudo ln -s $MOUNT_POINT/docker /var/lib/docker
fi
sudo systemctl start docker

# Clone or pull app repo
if [ ! -d "$MOUNT_POINT/apps/.git" ]; then
  git clone https://username:key/Consultlawal/test1.git $MOUNT_POINT/apps
else
  cd $MOUNT_POINT/apps && git pull
fi

# Start app using Docker Compose
if [ -f "$MOUNT_POINT/apps/docker-compose.yml" ]; then
  cd $MOUNT_POINT/apps
  docker compose up -d || docker-compose up -d
fi

# Notify ASG lifecycle hook
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
ASG_NAME="amj-raj-system-dev-prod-asg"

aws autoscaling complete-lifecycle-action \
  --lifecycle-hook-name wait-for-app-ready \
  --auto-scaling-group-name "$ASG_NAME" \
  --lifecycle-action-result CONTINUE \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"

echo "Setup completed successfully."



# #!/bin/bash

# # Update system
# apt-get update -y

# # --- Install AWS SSM Agent ---
# if ! systemctl is-active --quiet amazon-ssm-agent; then
#   snap install amazon-ssm-agent --classic || apt-get install -y amazon-ssm-agent
# fi
# systemctl enable amazon-ssm-agent
# systemctl start amazon-ssm-agent

# # --- Install AWS CLI v2 ---
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
# apt-get install -y unzip
# unzip awscliv2.zip
# ./aws/install
# aws --version

# # --- Install Docker ---
# curl -fsSL https://get.docker.com -o get-docker.sh
# sh get-docker.sh
# rm get-docker.sh

# # Add 'ubuntu' to docker group
# usermod -aG docker ubuntu

# # Enable and start Docker
# systemctl enable docker
# systemctl start docker

# # --- Install Docker Compose ---
# apt-get install -y docker-compose-plugin docker-compose
# docker compose version

# # --- Set Hostname ---
# hostnamectl set-hostname prodtest-server

# # --- Resize Root EBS Volume (xvda) ---
# apt-get install -y cloud-guest-utils
# growpart /dev/xvda 1

# FS_TYPE=$(lsblk -f /dev/xvda1 | awk 'NR==2 {print $2}')
# if [ "$FS_TYPE" = "xfs" ]; then
#   xfs_growfs /
# elif [ "$FS_TYPE" = "ext4" ]; then
#   resize2fs /dev/xvda1
# else
#   echo "Unsupported filesystem type: $FS_TYPE"
#   exit 1
# fi

# # --- Format and Mount Additional EBS Volume (e.g. /dev/nvme1n1) ---
# DEVICE="/dev/nvme1n1"
# MOUNT_POINT="/mnt/data"

# # Wait for the device to appear (retry up to 60s)
# for i in {1..12}; do
#   if lsblk | grep -q "$(basename $DEVICE)"; then
#     echo "Device $DEVICE is available."
#     break
#   fi
#   echo "Waiting for $DEVICE to become available..."
#   sleep 5
# done

# # Format if not already formatted
# if ! blkid $DEVICE; then
#   echo "$DEVICE is not formatted. Formatting as ext4..."
#   mkfs.ext4 $DEVICE
# fi

# # Mount the volume
# mkdir -p $MOUNT_POINT
# mount $DEVICE $MOUNT_POINT

# # Add to fstab if not already there
# if ! grep -qs "$DEVICE" /etc/fstab; then
#   UUID=$(blkid -s UUID -o value $DEVICE)
#   echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
# fi

# # --- Prepare App Directory ---
# mkdir -p $MOUNT_POINT/apps

# # --- Clone App Repo ---
# git clone https://usernaem:gitkey@github.com/Consultlawal/test1.git $MOUNT_POINT/apps

# # --- Move App Files (if previously in /root/test) ---
# if [ -d "/root/test" ]; then
#   mv /root/test/* $MOUNT_POINT/apps/
#   chmod -R 775 $MOUNT_POINT/apps/
# fi

# # --- Start App Using Docker Compose ---
# if [ -f $MOUNT_POINT/apps/docker-compose.yml ]; then
#   cd $MOUNT_POINT/apps
#   docker compose up -d || docker-compose up -d
# fi

# # --- Final Service Restart ---
# systemctl restart docker

# echo "Setup completed successfully."
