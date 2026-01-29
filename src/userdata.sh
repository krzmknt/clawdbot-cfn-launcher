#!/bin/bash
#
# Clawdbot EC2 UserData script
#
# This script is embedded into the CloudFormation template at deployment time.
# Placeholders ({{PLACEHOLDER}}) are replaced by install.sh.
#

set -euxo pipefail

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Clawdbot Setup ==="

# System updates
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
  docker.io \
  docker-compose \
  awscli \
  jq \
  unzip \
  curl \
  git

# Start Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Create Clawdbot directory
mkdir -p /opt/clawdbot
chown ubuntu:ubuntu /opt/clawdbot
cd /opt/clawdbot

# Create .env file (API keys to be configured via Clawdbot WebUI)
cat > /opt/clawdbot/.env << EOF
S3_DATA_BUCKET={{DATA_BUCKET}}
AWS_REGION={{AWS_REGION}}
EOF

chmod 600 /opt/clawdbot/.env
chown ubuntu:ubuntu /opt/clawdbot/.env

# Create docker-compose.yml
cat > /opt/clawdbot/docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  clawdbot:
    image: ghcr.io/clawdbot/clawdbot:latest
    container_name: clawdbot
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data:/app/data
      - ./config:/app/config
      - ./skills:/app/skills
    ports:
      - "3000:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
COMPOSE_EOF

# Create data directories
mkdir -p /opt/clawdbot/{data,config,skills}
chown -R ubuntu:ubuntu /opt/clawdbot

# Create systemd service for auto-start
cat > /etc/systemd/system/clawdbot.service << 'SERVICE_EOF'
[Unit]
Description=Clawdbot AI Agent
Requires=docker.service
After=docker.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/clawdbot
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Enable and start service
systemctl daemon-reload
systemctl enable clawdbot
systemctl start clawdbot

# Note: Backup is handled by EventBridge + SSM Run Command (configured in CloudFormation)
# Backup script is not needed here as SSM Document handles it

# Install CloudWatch agent for monitoring
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "Clawdbot",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/clawdbot/system",
            "log_stream_name": "user-data"
          }
        ]
      }
    }
  }
}
CW_EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== Clawdbot Setup Complete ==="
