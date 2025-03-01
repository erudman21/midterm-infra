#!/bin/bash
set -e

sudo yum update -y
sudo yum install -y docker aws-cli
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

# Create working directory
mkdir -p /app
cd /app
mkdir -p database

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

cat > database/init.sql << 'EOL_SQL'
use userdb;

CREATE TABLE `users` (`id` bigint(20) UNSIGNED NOT NULL, `first_name` varchar(200) NOT NULL, `last_name` varchar(200) NOT NULL, `email` varchar(200) DEFAULT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `users` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `id` (`id`);

ALTER TABLE `users` MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;
EOL_SQL

# Login to ECR
sudo AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN} aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Start the application
sudo ECR_REGISTRY=${ECR_REGISTRY} IMAGE_TAG=${IMAGE_TAG} docker compose up -d

# Wait for MySQL to initialize
sleep 60

cat > smoke_test.sh << 'EOL_SMOKE'
#!/bin/bash
set -e

# Test frontend
if ! curl --silent --fail --max-time 10 http://localhost:80; then
    echo "Frontend failed"
    exit 1
fi
echo "Frontend works"

# Test backend
if ! curl --silent --fail --max-time 10 http://localhost:9080/users; then
    echo "Backend failed"
    exit 1
fi
echo "Backend works"

# Test basic db stuff
create_response=$(curl -s -X POST -H "Content-Type: application/json" -d '{"firstName":"Test","lastName":"User","email":"test@example.com"}' http://localhost:9080/users)
if [[ "$create_response" != *"New user was created"* ]]; then
    echo "DB failed"
    exit 1
fi
echo "DB works"
echo "All smoke tests worked"
exit 0
EOL_SMOKE

chmod +x smoke_test.sh

# Run smoke tests
if ./smoke_test.sh; then
  echo "Tests passed" > /tmp/test_result.txt
  
  # Tag images with latest
  MANIFEST=$(aws ecr batch-get-image --repository-name midterm/frontend --image-ids imageTag=${IMAGE_TAG} --query 'images[].imageManifest' --output text)
  aws ecr put-image --repository-name midterm/frontend --image-tag latest --image-manifest "$MANIFEST"
  MANIFEST=$(aws ecr batch-get-image --repository-name midterm/backend --image-ids imageTag=${IMAGE_TAG} --query 'images[].imageManifest' --output text)
  aws ecr put-image --repository-name midterm/backend --image-tag latest --image-manifest "$MANIFEST"
  
  Invoke Lambda function for deployment
  aws lambda invoke \
    --function-name ${LAMBDA_ARN} \
    --payload '{"ecr_registry":"'${ECR_REGISTRY}'"}' \
    /tmp/lambda-response.json
  
  echo "Lambda response:"
  cat /tmp/lambda-response.json
else
  echo "Tests failed" > /tmp/test_result.txt
  
  # Delete failed images from ECR
  aws ecr batch-delete-image --repository-name midterm/frontend --image-ids imageTag=${IMAGE_TAG}
  aws ecr batch-delete-image --repository-name midterm/backend --image-ids imageTag=${IMAGE_TAG}
fi