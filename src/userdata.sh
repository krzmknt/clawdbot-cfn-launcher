#!/bin/bash
#
# Molt Bot EC2 UserData script
#
# This script is embedded into the CloudFormation template at deployment time.
# Placeholders ({{PLACEHOLDER}}) are replaced by install.sh.
#

set -euxo pipefail

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Molt Bot Setup ==="

# Wait for automatic apt processes to finish (unattended-upgrades, etc.)
echo "Waiting for apt locks to be released..."
while fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for other apt process to finish..."
  sleep 5
done
echo "apt locks released, proceeding..."

# System updates
apt-get update -y
apt-get upgrade -y

# Install dependencies
apt-get install -y \
  awscli \
  jq \
  unzip \
  curl \
  git

#============================================================================
# Install Node.js 22 (required for Molt Bot)
#============================================================================
echo "Installing Node.js 22..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Verify Node.js installation
node --version
npm --version

#============================================================================
# Install Molt Bot
#============================================================================
echo "Installing Molt Bot..."

# Create moltbot directory
mkdir -p /opt/moltbot
chown ubuntu:ubuntu /opt/moltbot

# Install moltbot globally
npm install -g moltbot@latest

# Run onboarding and install daemon as ubuntu user
# Note: --install-daemon sets up systemd service automatically
su - ubuntu -c "cd /opt/moltbot && moltbot onboard --install-daemon" || true

#============================================================================
# Create systemd service (fallback if onboard doesn't create it)
#============================================================================
if [ ! -f /etc/systemd/system/moltbot.service ]; then
  cat > /etc/systemd/system/moltbot.service << 'SERVICE_EOF'
[Unit]
Description=Molt Bot AI Agent
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/moltbot
ExecStart=/usr/bin/moltbot start
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICE_EOF

  systemctl daemon-reload
  systemctl enable moltbot
fi

#============================================================================
# Configure environment
#============================================================================
cat > /opt/moltbot/.env << EOF
S3_DATA_BUCKET={{DATA_BUCKET}}
AWS_REGION={{AWS_REGION}}
EOF

chmod 600 /opt/moltbot/.env
chown ubuntu:ubuntu /opt/moltbot/.env

#============================================================================
# Start Molt Bot
#============================================================================
systemctl start moltbot || true

# Note: Backup is handled by EventBridge + SSM Run Command (configured in CloudFormation)

#============================================================================
# Install CloudWatch agent for monitoring
#============================================================================
echo "Installing CloudWatch agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "MoltBot",
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
            "log_group_name": "/moltbot/system",
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

echo "=== Molt Bot Setup Complete ==="
echo "Access the dashboard with: moltbot dashboard"
