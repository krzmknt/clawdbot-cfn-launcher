#!/bin/bash
#
# View Moltbot logs
#
# Usage:
#   ./logs.sh <stack-name>              # Tail application logs
#   ./logs.sh <stack-name> --system     # View system/setup logs
#   ./logs.sh <stack-name> --all        # View all logs
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.config"

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Load config for REGION
[[ -f "$CONFIG_FILE" ]] || error "Config not found. Run install.sh first."
source "$CONFIG_FILE"

# Parse arguments
LOG_TYPE="app"
FOLLOW=true
LIMIT=100
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --system|-s)
      LOG_TYPE="system"
      shift
      ;;
    --all|-a)
      LOG_TYPE="all"
      shift
      ;;
    --no-follow)
      FOLLOW=false
      shift
      ;;
    --limit|-n)
      LIMIT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 <stack-name> [OPTIONS]"
      echo ""
      echo "Arguments:"
      echo "  stack-name      CloudFormation stack name"
      echo ""
      echo "Options:"
      echo "  --system, -s    View system/setup logs"
      echo "  --all, -a       View all log groups"
      echo "  --no-follow     Don't tail logs"
      echo "  --limit, -n N   Number of log events (default: 100)"
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

case $LOG_TYPE in
  app)
    LOG_GROUP="/moltbot/${STACK_NAME}"
    ;;
  system)
    LOG_GROUP="/moltbot/system"
    ;;
  all)
    info "Available log groups:"
    aws logs describe-log-groups \
      --log-group-name-prefix "/moltbot" \
      --region "$REGION" \
      --query 'logGroups[*].logGroupName' \
      --output table
    exit 0
    ;;
esac

info "Fetching logs from: $LOG_GROUP"
echo ""

if $FOLLOW; then
  # Tail logs
  aws logs tail "$LOG_GROUP" \
    --region "$REGION" \
    --follow \
    --format short
else
  # Get recent logs
  aws logs tail "$LOG_GROUP" \
    --region "$REGION" \
    --since 1h \
    --format short
fi
