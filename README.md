# Clawdbot on AWS

Deploy [Clawdbot](https://github.com/clawdbot/clawdbot) - a 24/7 AI Agent - on AWS EC2 with one command.

## Features

- 🚀 One-liner deployment via CloudFormation
- 🔒 Zero inbound ports (Session Manager only)
- 💰 ~$14/month (t4g.small + EBS)
- 🤖 Discord integration ready
- 📦 Auto backup to S3
- 📊 CloudWatch logging & monitoring

## Quick Start

> ⚠️ **Before running**: Ensure AWS CLI is authenticated.
>
> ```bash
> aws sts get-caller-identity  # Should return your AWS account info
> ```

```bash
curl -fsSL https://raw.githubusercontent.com/krzmknt/clawdbot-cfn-launcher/main/install.sh | bash
```

The installer will interactively guide you through configuration options including stack name, region, instance size, availability level, and security level.

## Prerequisites

- AWS CLI configured (`aws configure`)
- [Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (required for EC2 access)

## Architecture

```
┌───────────────────────────────────────────────────────┐
│                          VPC                          │
│  ┌─────────────────────────────────────────────────┐  │
│  │                   Public Subnet                 │  │
│  │  ┌───────────────────────────────────────────┐  │  │
│  │  │                    EC2                    │  │  │
│  │  │  ┌─────────────────────────────────────┐  │  │  │
│  │  │  │               Docker                │  │  │  │
│  │  │  │  ┌───────────────────────────────┐  │  │  │  │
│  │  │  │  │          Clawdbot             │  │  │  │  │
│  │  │  │  │  • Discord Bot                │  │  │  │  │
│  │  │  │  │  • Claude API                 │  │  │  │  │
│  │  │  │  │  • Web UI (:3000)             │  │  │  │  │
│  │  │  │  └───────────────────────────────┘  │  │  │  │
│  │  │  └─────────────────────────────────────┘  │  │  │
│  │  └───────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
         │                  │                    │
         ▼                  ▼                    ▼
   ┌──────────┐        ┌──────────┐        ┌──────────┐
   │ Secrets  │        │    S3    │        │CloudWatch│
   │ Manager  │        │ (Backup) │        │  (Logs)  │
   └──────────┘        └──────────┘        └──────────┘
```

## Usage

After deployment, helper scripts are installed to `~/.clawdbot-cfn-launcher/`:

```bash
# List all deployed stacks
~/.clawdbot-cfn-launcher/list.sh

# Connect to instance (shell)
~/.clawdbot-cfn-launcher/connect.sh <stack-name>

# Port forward to access WebUI
~/.clawdbot-cfn-launcher/connect.sh <stack-name> --port-forward
# Then open: http://localhost:3000

# View logs
~/.clawdbot-cfn-launcher/logs.sh <stack-name>

# Restart instance (reboot)
~/.clawdbot-cfn-launcher/restart.sh <stack-name>

# Restart instance (terminate and replace)
~/.clawdbot-cfn-launcher/restart.sh <stack-name> --replace

# Destroy stack (deletes everything including S3 data)
~/.clawdbot-cfn-launcher/destroy.sh <stack-name>
```

## Cost Breakdown

Costs vary by region. The installer fetches current pricing from AWS Pricing API.

**Example (us-east-1):**

| Resource      | Monthly Cost   |
| ------------- | -------------- |
| EC2 t4g.small | ~$12           |
| EBS 20GB gp3  | ~$2            |
| S3            | Usage-based    |
| **Total**     | **~$14/month** |

## Configuration

### Instance Types

| Type        | vCPU | RAM  | Use Case       |
| ----------- | ---- | ---- | -------------- |
| t4g.micro   | 2    | 1GB  | Testing        |
| t4g.small   | 2    | 2GB  | Recommended    |
| t4g.medium  | 2    | 4GB  | Standard       |
| t4g.large   | 2    | 8GB  | Multi-agent    |
| t4g.xlarge  | 4    | 16GB | Heavy workload |
| t4g.2xlarge | 8    | 32GB | Maximum        |

### EBS Volume Sizes

| Size    | Use Case   |
| ------- | ---------- |
| 20GB    | Minimal    |
| 50GB    | Standard   |
| 100GB   | Extended   |
| 200GB   | Large      |
| 500GB   | Very Large |
| 1000GB  | Maximum    |
| Custom  | 8-16000GB  |

### Availability Levels

| Feature                    | Low | Medium | High |
| -------------------------- | --- | ------ | ---- |
| Auto Scaling Group         | ✓   | ✓      | ✓    |
| ASG Size                   | 1   | 1      | 1-2  |
| Multi-AZ                   | -   | -      | ✓    |
| Auto Recovery              | ✓   | ✓      | ✓    |
| RTO (Recovery Time)        | ~1h | ~10min | ~2min |

### Backup Frequency

Backups are managed via EventBridge + SSM Run Command. S3 bucket is always created.

| Frequency   | RPO         | Schedule                    |
| ----------- | ----------- | --------------------------- |
| None        | N/A         | No automatic backups        |
| Daily       | ~24 hours   | Once per day at 3:00 AM UTC |
| Hourly      | ~1 hour     | Every hour                  |
| 5 minutes   | ~5 min      | Every 5 minutes             |

Backup frequency can be changed later via CloudFormation stack update.

### Security Levels

| Feature                    | Normal | High | Highest |
| -------------------------- | ------ | ---- | ------- |
| **Network**                |        |      |         |
| Public Subnet              | ✓      | ✓    | -       |
| Private Subnet             | -      | -    | ✓       |
| NAT Gateway                | -      | -    | ✓       |
| **Base Security**          |        |      |         |
| SSM Session Manager        | ✓      | ✓    | ✓       |
| Encrypted EBS              | ✓      | ✓    | ✓       |
| No Inbound Ports           | ✓      | ✓    | ✓       |
| **Logging & Monitoring**   |        |      |         |
| VPC Flow Logs              | -      | ✓    | ✓       |
| CloudTrail                 | -      | ✓    | ✓       |
| **Advanced**               |        |      |         |
| VPC Endpoints              | -      | -    | ✓       |
| GuardDuty                  | -      | -    | ✓       |

## Security

- **No inbound ports** - All access via Session Manager
- **IAM authentication** - No SSH keys to manage
- **Encrypted EBS** - Data at rest encryption
- **CloudTrail logging** - All access is audited (Security Level: High+)
- **Private Subnet** - No public IP, outbound via NAT Gateway (Security Level: Highest)

## Troubleshooting

### Can't connect via Session Manager

1. Check SSM agent is running:

   ```bash
   aws ssm describe-instance-information --region <region>
   ```

2. Verify IAM role has `AmazonSSMManagedInstanceCore` policy

3. Check instance is running:
   ```bash
   aws ec2 describe-instances --instance-ids <id> --query 'Reservations[*].Instances[*].State.Name'
   ```

### Clawdbot not starting

1. Check logs:

   ```bash
   ~/.clawdbot-cfn-launcher/logs.sh <stack-name> --system
   ```

2. Connect and check Docker:
   ```bash
   ~/.clawdbot-cfn-launcher/connect.sh <stack-name>
   # Then on instance:
   docker ps
   docker logs clawdbot
   ```

## Manual Deployment

If you prefer manual deployment:

```bash
# Download template
curl -O https://raw.githubusercontent.com/krzmknt/clawdbot-cfn-launcher/main/src/cfn-template.yml

# Deploy
aws cloudformation create-stack \
  --stack-name clawdbot \
  --template-body file://cfn-template.yml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=InstanceType,ParameterValue=t4g.small \
    ParameterKey=DataVolumeSize,ParameterValue=20

# After deployment, access WebUI to configure API keys
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
# Then open: http://localhost:3000
```

## License

MIT

## Contributing

PRs welcome!
