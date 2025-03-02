#!/bin/bash

# Function to terminate the instance regardless of where the script fails
terminate_instance() {
  echo "Terminating instance..."
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-east-1
}

trap terminate_instance EXIT ERR SIGINT SIGTERM

set -e

source ./env.sh
./setup.sh

# Create application directory
sudo mkdir -p /app
sudo mkdir -p /app/database
sudo chmod 777 -R /app

cp docker-compose.yml /app/
cp database/init.sql /app/database/
cp smoke_test.sh /app/
chmod +x /app/smoke_test.sh

cd /app
sudo ECR_REGISTRY=${ECR_REGISTRY} IMAGE_TAG=${IMAGE_TAG} docker compose up -d

# Wait for MySQL to initialize
sleep 60

# Run smoke tests
if ./smoke_test.sh; then
  echo "Tests passed" > /tmp/test_result.txt
  
  # Tag images with latest
  MANIFEST=$(aws ecr batch-get-image --repository-name midterm/frontend --image-ids imageTag=${IMAGE_TAG} --query 'images[].imageManifest' --output text)
  aws ecr put-image --repository-name midterm/frontend --image-tag latest --image-manifest "$MANIFEST"
  MANIFEST=$(aws ecr batch-get-image --repository-name midterm/backend --image-ids imageTag=${IMAGE_TAG} --query 'images[].imageManifest' --output text)
  aws ecr put-image --repository-name midterm/backend --image-tag latest --image-manifest "$MANIFEST"
  
  # Invoke Lambda to deploy to QA environment
  PAYLOAD=$(echo -n '{
    "ecr_registry":"'"${ECR_REGISTRY}"'",
    "aws_credentials":{
      "access_key":"'"${AWS_ACCESS_KEY_ID}"'",
      "secret_key":"'"${AWS_SECRET_ACCESS_KEY}"'",
      "session_token":"'"${AWS_SESSION_TOKEN}"'"
    },
    "rds_credentials":{
      "rds_endpoint":"'"${RDS_ENDPOINT}"'",
      "db_name":"'"${DB_NAME}"'",
      "db_user":"'"${DB_USER}"'",
      "db_pass":"'"${DB_PASS}"'"
    }
  }' | base64)
  aws lambda invoke --function-name ${LAMBDA_ARN} --payload "$PAYLOAD" /tmp/lambda-response.json
else
  echo "Tests failed" > /tmp/test_result.txt
  # Delete failed images from ECR
  aws ecr batch-delete-image --repository-name midterm/frontend --image-ids imageTag=${IMAGE_TAG}
  aws ecr batch-delete-image --repository-name midterm/backend --image-ids imageTag=${IMAGE_TAG}
fi

# Disable the trap before exiting normally
# This prevents duplicate termination attempts
trap - EXIT
terminate_instance