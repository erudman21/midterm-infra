#!/bin/bash

# Function to terminate the instance regardless of where the script fails
terminate_instance() {
  echo "Terminating instance..."
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-east-1
}

# trap terminate_instance EXIT ERR SIGINT SIGTERM

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
  
  # Get the workflow run ID of the current workflow
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
  
  # Get tags
  INSTANCE_DATA=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region us-east-1)
  WORKFLOW_RUN_ID=$(echo $INSTANCE_DATA | grep -o '"Name": "workflow_run_id", "Value": "[^"]*"' | cut -d'"' -f6)
  
  if [ -z "$WORKFLOW_RUN_ID" ]; then
    # If no tag is found, use a default value
    WORKFLOW_RUN_ID="unknown"
  fi
  
  # Trigger GitHub Actions workflow for QA deployment
  echo "Triggering QA deployment workflow..."
  curl -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/qa-deploy.yml/dispatches \
    -d "{
      \"ref\": \"${GITHUB_REF_NAME}\",
      \"inputs\": {
        \"image_tag\": \"${IMAGE_TAG}\",
        \"run_id\": \"${WORKFLOW_RUN_ID}\"
      }
    }"
    
  # Log the payload
  echo "Sending payload with IMAGE_TAG=${IMAGE_TAG}, WORKFLOW_RUN_ID=${WORKFLOW_RUN_ID}"
else
  echo "Tests failed" > /tmp/test_result.txt

  # Delete failed images from ECR
  aws ecr batch-delete-image --repository-name midterm/frontend --image-ids imageTag=${IMAGE_TAG}
  aws ecr batch-delete-image --repository-name midterm/backend --image-ids imageTag=${IMAGE_TAG}

  cat > /tmp/github_api_debug.txt << EOF
  API URL: https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/qa-deploy.yml/dispatches
  GITHUB_TOKEN: ${GITHUB_TOKEN}
  GITHUB_REPOSITORY: ${GITHUB_REPOSITORY}
  GITHUB_REF_NAME: ${GITHUB_REF_NAME}
  IMAGE_TAG: ${IMAGE_TAG}
  WORKFLOW_RUN_ID: ${WORKFLOW_RUN_ID}

  Full payload:
  {
    "ref": "${GITHUB_REF_NAME}",
    "inputs": {
      "image_tag": "${IMAGE_TAG}",
      "run_id": "${WORKFLOW_RUN_ID}",
      "status": "integration tests failed"
    }
  }
  EOF

  echo "Triggering QA deployment workflow with test failure notification..."
  curl -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/qa-deploy.yml/dispatches \
    -d "{
      \"ref\": \"${GITHUB_REF_NAME}\",
      \"inputs\": {
        \"image_tag\": \"${IMAGE_TAG}\",
        \"run_id\": \"${WORKFLOW_RUN_ID}\",
        \"status\": \"integration tests failed\"
      }
    }"
    
  # Log the payload
  echo "Sending payload with IMAGE_TAG=${IMAGE_TAG}, WORKFLOW_RUN_ID=${WORKFLOW_RUN_ID}, status=integration tests failed"
fi

# Wait for a few seconds to make sure the curl request finishes
sleep 10
echo "QA deployment workflow triggered"

# trap - EXIT
# terminate_instance