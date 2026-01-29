#!/bin/bash
#
# List all Clawdbot CloudFormation stacks
#
# Usage:
#   ./list.sh              # List stacks in table format
#   ./list.sh --verbose    # Show more details
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Load config for REGION
[[ -f "$CONFIG_FILE" ]] || error "Config not found. Run install.sh first."
source "$CONFIG_FILE"

# Parse arguments
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --verbose, -v    Show detailed information"
      echo "  --help, -h       Show this help"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

info "Listing Clawdbot stacks in region: $REGION"
echo ""

# Get stacks with "clawdbot" in their description
STACKS=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --query 'Stacks[?contains(Description, `Clawdbot`) || contains(StackName, `clawdbot`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' \
  --output json 2>/dev/null)

if [[ "$STACKS" == "[]" || -z "$STACKS" ]]; then
  echo "No Clawdbot stacks found."
  echo ""
  echo "To deploy a new stack, run:"
  echo "  ./install.sh"
  exit 0
fi

if $VERBOSE; then
  # Detailed output
  echo "$STACKS" | jq -r '.[] | "Stack Name: \(.Name)\nStatus:     \(.Status)\nCreated:    \(.Created)\n---"'

  echo ""
  info "Stack details:"
  echo ""

  for STACK_NAME in $(echo "$STACKS" | jq -r '.[].Name'); do
    echo -e "${GREEN}$STACK_NAME${NC}"

    # Get outputs
    aws cloudformation describe-stacks \
      --stack-name "$STACK_NAME" \
      --region "$REGION" \
      --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
      --output table 2>/dev/null | head -20

    echo ""
  done
else
  # Simple table output
  printf "%-30s %-20s %s\n" "STACK NAME" "STATUS" "CREATED"
  printf "%-30s %-20s %s\n" "----------" "------" "-------"

  echo "$STACKS" | jq -r '.[] | "\(.Name)|\(.Status)|\(.Created)"' | while IFS='|' read -r name status created; do
    # Color status
    case $status in
      CREATE_COMPLETE|UPDATE_COMPLETE)
        status_colored="${GREEN}${status}${NC}"
        ;;
      *_IN_PROGRESS)
        status_colored="${YELLOW}${status}${NC}"
        ;;
      *_FAILED|DELETE_*)
        status_colored="${RED}${status}${NC}"
        ;;
      *)
        status_colored="$status"
        ;;
    esac

    # Format date
    created_short=$(echo "$created" | cut -d'T' -f1)

    printf "%-30s %-20b %s\n" "$name" "$status_colored" "$created_short"
  done
fi

echo ""
info "Commands:"
echo "  connect.sh <stack-name>           Connect to EC2 instance"
echo "  logs.sh <stack-name>              View logs"
echo "  destroy.sh <stack-name>           Delete stack"
