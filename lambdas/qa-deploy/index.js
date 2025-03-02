const { Client } = require('ssh2');

// Function to create an SSH connection
async function createSSHConnection(host, privateKey) {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    conn.on('ready', () => {
      console.log('SSH connection established');
      resolve(conn);
    }).on('error', (err) => {
      console.error('SSH connection error:', err);
      reject(err);
    }).connect({
      host: host,
      username: 'ec2-user',
      privateKey: privateKey
    });
  });
}

async function executeCommand(conn, command) {
  return new Promise((resolve, reject) => {
    conn.exec(command, (err, stream) => {
      if (err) {
        reject(err);
        return;
      }
      
      let stdout = '';
      let stderr = '';
      
      stream.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(`Command failed with code ${code}: ${stderr}`));
        } else {
          resolve(stdout);
        }
      }).on('data', (data) => {
        stdout += data.toString();
      }).stderr.on('data', (data) => {
        stderr += data.toString();
      });
    });
  });
}

exports.handler = async (event) => {
  let conn;
  
  try {
    const qaServerIp = process.env.QA_SERVER_IP;
    const ecrRegistry = event.ecr_registry;
    const credentials = event.aws_credentials;
    const dbInfo = event.rds_credentials;
    
    // Connect to the QA EC2 instance
    const formattedKey = process.env.QA_SSH_KEY.replace(/\\n/g, '\n');
    conn = await createSSHConnection(qaServerIp, formattedKey);
    
    const deployCommand = `
      export AWS_ACCESS_KEY_ID="${credentials.access_key}"
      export AWS_SECRET_ACCESS_KEY="${credentials.secret_key}"
      export AWS_SESSION_TOKEN="${credentials.session_token}"
      export RDS_ENDPOINT="${dbInfo.rds_endpoint}"
      export DB_USER="${dbInfo.db_user}"
      export DB_PASS="${dbInfo.db_pass}"
      export DB_NAME="${dbInfo.db_name}"
      
      # Login to ECR
      aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${ecrRegistry}
      
      # Stop current containers
      cd ~/app
      sudo docker compose down

      # Start with new images
      sudo docker compose up -d
      
      # Check if Nginx is running, restart if needed
      if ! systemctl is-active --quiet nginx; then
        sudo systemctl restart nginx
      fi
      
      echo "Deployment completed at $(date)"
    `;
    
    const output = await executeCommand(conn, deployCommand);
    console.log('Deployment output:', output);
    
    conn.end();
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Deployment completed successfully',
        output: output
      })
    };
  } catch (error) {
    console.error('Error during deployment:', error);
    
    if (conn) conn.end();
    
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Deployment failed',
        error: error.message
      })
    };
  }
};