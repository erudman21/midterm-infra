#!/bin/bash
set -e

sudo yum update -y
sudo yum install -y docker aws-cli
systemctl start docker

# Create working directory
mkdir -p /app
cd /app

cat > docker-compose.yml << 'EOL_COMPOSE'
version: '3.8'

services:
  frontend:
    image: ${ECR_REGISTRY}/midterm/frontend:${IMAGE_TAG}
    ports:
      - "80:80"
    restart: always
    depends_on:
      - backend

  backend:
    image: ${ECR_REGISTRY}/midterm/backend:${IMAGE_TAG}
    environment:
      - DB_HOST=db
      - DB_PORT=3306
      - DB_USER=root
      - DB_PASS=mysql987
      - DB_NAME=userdb
    ports:
      - "9080:9080"
    restart: always
    depends_on:
      - db

  db:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=mysql987
      - MYSQL_DATABASE=userdb
    volumes:
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
      - ./my-data-2:/var/lib/mysql
    ports:
      - "3306:3306"

volumes:
  my-data-2:

EOL_COMPOSE

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Start the application
ECR_REGISTRY=${ECR_REGISTRY} IMAGE_TAG=${IMAGE_TAG} docker-compose up -d

# Wait for MySQL to initialize
sleep 30

echo "Application started"