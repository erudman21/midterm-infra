const { Client } = require('ssh2');

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
    const ecrRegistry = event.ecr_registry;
    const qaServerIp = process.env.QA_SERVER_IP;
    const qaSSHKey = process.env.QA_SSH_KEY;
    
    // Connect to the QA EC2 instance
    const formattedKey = process.env.QA_SSH_KEY.replace(/\\n/g, '\n');
    conn = await createSSHConnection(qaServerIp, formattedKey);
    
    // Build the deployment command
    const deployCommand = `
      # Login to ECR
      aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${ecrRegistry}
      
      # Stop current containers
      cd ~/app
      docker compose down

      # Start with new images
      docker compose up -d
      
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