#!/bin/bash
#
# Connect to Moltbot EC2 instance via Session Manager
#
# Usage:
#   ./connect.sh <stack-name>                    # Shell access
#   ./connect.sh <stack-name> --port-forward     # Port forward (WebUI at localhost:3000)
#   ./connect.sh <stack-name> --port 8080        # Custom local port
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Load config for REGION
[[ -f "$CONFIG_FILE" ]] || error "Config not found. Run install.sh first."
source "$CONFIG_FILE"

# Parse arguments
PORT_FORWARD=false
LOCAL_PORT=3000
REMOTE_PORT=3000
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --port-forward|-p)
      PORT_FORWARD=true
      shift
      ;;
    --port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --remote-port)
      REMOTE_PORT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 <stack-name> [OPTIONS]"
      echo ""
      echo "Arguments:"
      echo "  stack-name            CloudFormation stack name"
      echo ""
      echo "Options:"
      echo "  --port-forward, -p    Enable port forwarding"
      echo "  --port PORT           Local port (default: 3000)"
      echo "  --remote-port PORT    Remote port (default: 3000)"
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

if $PORT_FORWARD; then
  info "Starting port forward: localhost:$LOCAL_PORT -> EC2:$REMOTE_PORT"
  info "Access Moltbot WebUI at: http://localhost:$LOCAL_PORT"
  echo ""
  aws ssm start-session \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
    --region "$REGION"
else
  info "Connecting to instance: $INSTANCE_ID"
  echo ""
  aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$REGION"
fi
