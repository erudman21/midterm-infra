#!/bin/bash
# Setup script to install dependencies and configure the environment
set -e

source ./env.sh

sudo yum update -y
sudo yum install -y docker awscli

sudo systemctl start docker

sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -L "https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

mkdir -p ~/.aws
cat > ~/.aws/credentials << EOL
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
aws_session_token=${AWS_SESSION_TOKEN}
EOL

aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${ECR_REGISTRY}