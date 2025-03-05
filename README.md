# Infra repo for 686 midterm

## Workflows
### Nightly Deployment
Initializes the temp EC2, builds and pushes the images to ECR, runs the smoke tests on the temp EC2. The image pushed to ECR will be deleted if the smoke tests fail or re-tagged with "latest" if the smoke tests pass.

**Important** This workflow finishes immediately after the smoke tests are kicked off (so before they finish)

### QA Deployment
This workflow is triggered from within the temp EC2 (using a curl request) after the smoke tests run.
#### If the smoke tests are successful:
Basically just SSHs into the QA EC2 and runs docker compose down/up (with the new image tag)
#### If the smoke tests fail:
This workflow will fail and provides the image tag that caused the failure

## Secrets
The repo has the following set as repo secrets in GitHub:
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_SESSION_TOKEN
- DB_NAME
- DB_PASS
- DB_USER
- DEPLOY_PAT
- PUBLIC_SUBNET_ID
- QA_SERVER_IP
- RDS_ENDPOINT
- SSH_KEY
- TEMP_EC2_SECURITY_GROUP

## Visual
![Screenshot 2025-03-02 235904](https://github.com/user-attachments/assets/ca78f038-4e0a-4fc9-b0ee-99711f47e070)
