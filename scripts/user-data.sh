#!/bin/bash
set -e

sudo yum update -y
sudo yum install -y docker aws-cli
systemctl start docker

# Create working directory
mkdir -p /app
cd /app

cat > docker-compose.yml << 'EOL_COMPOSE'
${DOCKER_COMPOSE}
EOL_COMPOSE

cat > database/init.sql << 'EOL_SQL'
${SQL_INIT}
EOL_SQL

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Start the application
ECR_REGISTRY=${ECR_REGISTRY} IMAGE_TAG=${IMAGE_TAG} docker-compose up -d

# Wait for MySQL to initialize
sleep 30

echo "Application started"