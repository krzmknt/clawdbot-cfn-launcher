#!/bin/bash
#
# Restart Clawdbot EC2 instance
#
# Usage:
#   ./restart.sh <stack-name>                  # Reboot instance
#   ./restart.sh <stack-name> --replace        # Terminate and let ASG launch new instance
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Load config for REGION
[[ -f "$CONFIG_FILE" ]] || error "Config not found. Run install.sh first."
source "$CONFIG_FILE"

# Parse arguments
REPLACE=false
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --replace|-r)
      REPLACE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <stack-name> [OPTIONS]"
      echo ""
      echo "Arguments:"
      echo "  stack-name            CloudFormation stack name"
      echo ""
      echo "Options:"
      echo "  --replace, -r         Terminate instance and let ASG launch new one"
      echo "                        (Use this if instance is unhealthy)"
      echo ""
      echo "Default behavior: Reboot the instance (faster, keeps same instance)"
      echo ""
      echo "Use 'list.sh' to see available stacks."
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      ;;
    *)
      if [[ -z "$STACK_NAME" ]]; then
        STACK_NAME="$1"
      else
        error "Unknown argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -z "$STACK_NAME" ]] && error "Stack name is required. Usage: $0 <stack-name> [OPTIONS]"

# Get ASG name from stack
info "Getting Auto Scaling Group from stack: $STACK_NAME"
ASG_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text 2>/dev/null) || error "Failed to get ASG name. Is the stack deployed?"

[[ -z "$ASG_NAME" || "$ASG_NAME" == "None" ]] && error "Auto Scaling Group not found"

# Get instance ID from ASG
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text 2>/dev/null)

[[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]] && error "No running instance found in ASG"

info "Found instance: $INSTANCE_ID"

if $REPLACE; then
  warn "This will TERMINATE the instance and ASG will launch a new one."
  warn "Data not backed up to S3 will be LOST."
  echo ""
  read -p "Are you sure? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

  info "Terminating instance: $INSTANCE_ID"
  aws autoscaling terminate-instance-in-auto-scaling-group \
    --instance-id "$INSTANCE_ID" \
    --no-should-decrement-desired-capacity \
    --region "$REGION"

  success "Instance terminated. ASG will launch a new instance."
  info "Use 'list.sh' to check when new instance is ready."
else
  info "Rebooting instance: $INSTANCE_ID"
  aws ec2 reboot-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

  success "Reboot initiated. Instance will be available again in ~1-2 minutes."
fi
