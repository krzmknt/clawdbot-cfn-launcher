#!/bin/bash
#
# Destroy Moltbot CloudFormation stack
#
# Usage:
#   ./destroy.sh <stack-name>
#   ./destroy.sh <stack-name> --force    # Skip confirmation
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
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# Load config for REGION
[[ -f "$CONFIG_FILE" ]] || error "Config not found. Run install.sh first."
source "$CONFIG_FILE"

# Parse arguments
FORCE=false
STACK_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --force|-f)
      FORCE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <stack-name> [OPTIONS]"
      echo ""
      echo "Arguments:"
      echo "  stack-name     CloudFormation stack name"
      echo ""
      echo "Options:"
      echo "  --force, -f    Skip confirmation prompt"
      echo ""
      echo "This will completely delete:"
      echo "  - EC2 instance and Auto Scaling Group"
      echo "  - S3 buckets (including all backup data)"
      echo "  - VPC, subnets, and all network resources"
      echo "  - IAM roles and policies"
      echo "  - CloudWatch log groups"
      echo ""
      echo "You will be asked if you want to download the latest backup before deletion."
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

# Verify stack exists
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" &>/dev/null || error "Stack '$STACK_NAME' not found in region $REGION"

echo ""
echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║   ⚠️  WARNING: This will PERMANENTLY destroy everything   ║${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Stack Name: $STACK_NAME"
echo "  Region:     $REGION"
echo ""

# Get S3 bucket names from stack outputs
DATA_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
  --output text 2>/dev/null || echo "")

CLOUDTRAIL_BUCKET="${STACK_NAME}-cloudtrail-$(aws sts get-caller-identity --query Account --output text)"

# Show what will be deleted
info "The following will be PERMANENTLY deleted:"
echo ""
echo "  • EC2 instance and Auto Scaling Group"
echo "  • All network resources (VPC, subnets, etc.)"
echo "  • IAM roles and policies"
echo "  • CloudWatch log groups"
if [[ -n "$DATA_BUCKET" && "$DATA_BUCKET" != "None" ]]; then
  echo -e "  • ${RED}S3 bucket: $DATA_BUCKET (ALL BACKUP DATA)${NC}"
fi
echo -e "  • ${RED}S3 bucket: $CLOUDTRAIL_BUCKET (if exists)${NC}"
echo ""

# Check for backups and offer download
if [[ -n "$DATA_BUCKET" && "$DATA_BUCKET" != "None" ]]; then
  if aws s3api head-bucket --bucket "$DATA_BUCKET" 2>/dev/null; then
    # Find the latest backup
    LATEST_BACKUP=$(aws s3 ls "s3://$DATA_BUCKET/backups/" 2>/dev/null | sort | tail -n1 | awk '{print $2}' | tr -d '/')

    if [[ -n "$LATEST_BACKUP" ]]; then
      echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      info "Latest backup found: $LATEST_BACKUP"
      echo ""

      # Show backup size
      BACKUP_SIZE=$(aws s3 ls "s3://$DATA_BUCKET/backups/$LATEST_BACKUP" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}')
      if [[ -n "$BACKUP_SIZE" ]]; then
        # Convert bytes to human readable
        if [[ $BACKUP_SIZE -gt 1073741824 ]]; then
          BACKUP_SIZE_HR=$(echo "scale=2; $BACKUP_SIZE / 1073741824" | bc)GB
        elif [[ $BACKUP_SIZE -gt 1048576 ]]; then
          BACKUP_SIZE_HR=$(echo "scale=2; $BACKUP_SIZE / 1048576" | bc)MB
        elif [[ $BACKUP_SIZE -gt 1024 ]]; then
          BACKUP_SIZE_HR=$(echo "scale=2; $BACKUP_SIZE / 1024" | bc)KB
        else
          BACKUP_SIZE_HR="${BACKUP_SIZE}B"
        fi
        echo "  Backup size: $BACKUP_SIZE_HR"
      fi
      echo ""

      if ! $FORCE; then
        read -p "Download latest backup to local before deletion? (y/N): " download_backup
        if [[ "$download_backup" =~ ^[Yy]$ ]]; then
          DOWNLOAD_DIR="./moltbot-backup-${STACK_NAME}-${LATEST_BACKUP}"
          info "Downloading backup to: $DOWNLOAD_DIR"
          mkdir -p "$DOWNLOAD_DIR"
          aws s3 cp "s3://$DATA_BUCKET/backups/$LATEST_BACKUP" "$DOWNLOAD_DIR" --recursive
          success "Backup downloaded to: $DOWNLOAD_DIR"
          echo ""
        fi
      fi
      echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo ""
    else
      info "No backups found in S3 bucket."
      echo ""
    fi
  fi
fi

warn "ALL DATA WILL BE LOST. This action cannot be undone."
echo ""

if ! $FORCE; then
  read -p "Type the stack name to confirm deletion [$STACK_NAME]: " confirm
  [[ "$confirm" != "$STACK_NAME" ]] && { info "Deletion cancelled."; exit 0; }
fi

echo ""

# Empty S3 buckets before stack deletion (CloudFormation can't delete non-empty buckets)
empty_bucket() {
  local bucket=$1
  if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    info "Emptying S3 bucket: $bucket"
    # Delete all versions (for versioned buckets)
    aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[] | "--delete \"Objects=[{Key=\(.Key),VersionId=\(.VersionId)}]\""' 2>/dev/null | \
      xargs -I {} aws s3api delete-objects --bucket "$bucket" {} 2>/dev/null || true
    # Delete delete markers
    aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
      jq -r '.[] | "--delete \"Objects=[{Key=\(.Key),VersionId=\(.VersionId)}]\""' 2>/dev/null | \
      xargs -I {} aws s3api delete-objects --bucket "$bucket" {} 2>/dev/null || true
    # Delete all objects (simple delete for non-versioned)
    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    success "Emptied: $bucket"
  fi
}

# Empty buckets
if [[ -n "$DATA_BUCKET" && "$DATA_BUCKET" != "None" ]]; then
  empty_bucket "$DATA_BUCKET"
fi
empty_bucket "$CLOUDTRAIL_BUCKET" 2>/dev/null || true

# Delete CloudFormation stack
info "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

info "Waiting for stack deletion (this may take several minutes)..."
aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo ""
success "Stack '$STACK_NAME' has been completely destroyed!"
echo ""
info "All resources and data have been deleted. No ongoing charges."
info "Run 'install.sh' to deploy a new stack."
echo ""
