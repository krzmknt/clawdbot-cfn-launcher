#!/bin/bash
#
# Clawdbot on AWS - One-liner Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/krzmknt/clawdbot-cfn-launcher/main/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --stack-name my-clawdbot --region us-west-2
#

set -e

#============================================================================
# Configuration
#============================================================================
REPO_BASE_URL="https://raw.githubusercontent.com/krzmknt/clawdbot-cfn-launcher/main"
INSTALL_DIR="${CLAWDBOT_INSTALL_DIR:-$HOME/.clawdbot-cfn-launcher}"
STACK_NAME="clawdbot"
REGION=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#============================================================================
# Helper Functions
#============================================================================
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Convert region code to location name for AWS Pricing API
get_region_name() {
  case "$1" in
    us-east-1)      echo "US East (N. Virginia)" ;;
    us-east-2)      echo "US East (Ohio)" ;;
    us-west-1)      echo "US West (N. California)" ;;
    us-west-2)      echo "US West (Oregon)" ;;
    ap-south-1)     echo "Asia Pacific (Mumbai)" ;;
    ap-northeast-1) echo "Asia Pacific (Tokyo)" ;;
    ap-northeast-2) echo "Asia Pacific (Seoul)" ;;
    ap-northeast-3) echo "Asia Pacific (Osaka)" ;;
    ap-southeast-1) echo "Asia Pacific (Singapore)" ;;
    ap-southeast-2) echo "Asia Pacific (Sydney)" ;;
    ca-central-1)   echo "Canada (Central)" ;;
    eu-central-1)   echo "EU (Frankfurt)" ;;
    eu-west-1)      echo "EU (Ireland)" ;;
    eu-west-2)      echo "EU (London)" ;;
    eu-west-3)      echo "EU (Paris)" ;;
    eu-north-1)     echo "EU (Stockholm)" ;;
    sa-east-1)      echo "South America (Sao Paulo)" ;;
    *)              echo "US East (N. Virginia)" ;;
  esac
}

print_banner() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║                                                           ║${NC}"
  echo -e "${BLUE}║   ${GREEN}🤖 Clawdbot on AWS - Installer${BLUE}                         ║${NC}"
  echo -e "${BLUE}║                                                           ║${NC}"
  echo -e "${BLUE}║   24/7 AI Agent running on EC2 with Discord integration   ║${NC}"
  echo -e "${BLUE}║                                                           ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --install-dir DIR    Installation directory (default: ~/.clawdbot-cfn-launcher)
  --help               Show this help message

Example:
  curl -fsSL $REPO_BASE_URL/install.sh | bash

The installer will interactively guide you through all configuration options.

EOF
  exit 0
}

#============================================================================
# Parse Arguments
#============================================================================
while [[ $# -gt 0 ]]; do
  case $1 in
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      error "Unknown option: $1. Use --help for usage."
      ;;
  esac
done

#============================================================================
# Prerequisite Checks
#============================================================================
check_prerequisites() {
  info "Checking prerequisites..."

  # AWS CLI
  if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Install it from: https://aws.amazon.com/cli/"
  fi
  success "AWS CLI found"

  # AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    echo ""
    error "AWS credentials not configured or expired.

  Please authenticate first:
    • For IAM user:     aws configure
    • For SSO:          aws sso login --profile <profile>
    • For MFA:          aws sts get-session-token ...

  Verify with: aws sts get-caller-identity"
  fi

  # Show authenticated identity
  local identity
  identity=$(aws sts get-caller-identity --output json 2>/dev/null)
  local account_id arn
  account_id=$(echo "$identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
  arn=$(echo "$identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
  success "AWS credentials configured (Account: $account_id)"
  info "  Identity: $arn"

  # Session Manager plugin (required for connect.sh)
  if ! command -v session-manager-plugin &> /dev/null; then
    error "Session Manager plugin is not installed. Required for EC2 access.

  Install from:
    https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

  macOS:    brew install --cask session-manager-plugin
  Linux:    See AWS documentation above"
  fi
  success "Session Manager plugin found"

  # jq (required for pricing API)
  if ! command -v jq &> /dev/null; then
    error "jq is not installed. Required for JSON parsing.

  Install:
    macOS:    brew install jq
    Ubuntu:   sudo apt-get install jq
    Amazon Linux: sudo yum install jq"
  fi
  success "jq found"

  # bc (required for price calculation)
  if ! command -v bc &> /dev/null; then
    warn "bc not found. Price calculation may not work."
  fi

  echo ""
}

#============================================================================
# Download Files
#============================================================================
download_files() {
  info "Creating installation directory: $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"

  info "Downloading CloudFormation template..."
  curl -fsSL "$REPO_BASE_URL/src/cfn-template.yml" -o cfn-template.yml
  success "Downloaded cfn-template.yml"

  info "Downloading UserData script..."
  curl -fsSL "$REPO_BASE_URL/src/userdata.sh" -o userdata.sh
  success "Downloaded userdata.sh"

  info "Downloading helper scripts..."
  curl -fsSL "$REPO_BASE_URL/src/connect.sh" -o connect.sh
  curl -fsSL "$REPO_BASE_URL/src/logs.sh" -o logs.sh
  curl -fsSL "$REPO_BASE_URL/src/destroy.sh" -o destroy.sh
  curl -fsSL "$REPO_BASE_URL/src/list.sh" -o list.sh
  chmod +x *.sh
  success "Downloaded helper scripts"

  echo ""
}

#============================================================================
# Gather Parameters
#============================================================================
gather_parameters() {
  info "Gathering deployment parameters..."
  echo ""

  # Stack name
  read -p "Stack Name [$STACK_NAME]: " input_stack
  STACK_NAME="${input_stack:-$STACK_NAME}"

  # Region
  if [[ -z "$REGION" ]]; then
    DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"
    read -p "AWS Region [$DEFAULT_REGION]: " input_region
    REGION="${input_region:-$DEFAULT_REGION}"
  fi

  # EC2 Instance Type
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  EC2 Instance Size${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  info "Fetching current pricing for region: $REGION ..."

  # Instance specs (type, vCPU, RAM, use case)
  declare -a INSTANCE_TYPES=("t4g.micro" "t4g.small" "t4g.medium" "t4g.large" "t4g.xlarge" "t4g.2xlarge")
  declare -a INSTANCE_VCPU=("2" "2" "2" "2" "4" "8")
  declare -a INSTANCE_RAM=("1GB" "2GB" "4GB" "8GB" "16GB" "32GB")
  declare -a INSTANCE_USE=("Testing" "Recommended" "Standard" "Multi-agent" "Heavy workload" "Maximum")

  # Fetch all t4g prices in one API call
  LOCATION_NAME=$(get_region_name "$REGION")
  PRICE_DATA=$(aws pricing get-products \
    --service-code AmazonEC2 \
    --region us-east-1 \
    --filters \
      "Type=TERM_MATCH,Field=instanceFamily,Value=General purpose" \
      "Type=TERM_MATCH,Field=location,Value=$LOCATION_NAME" \
      "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" \
      "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
      "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
      "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" \
    --output json 2>/dev/null || echo '{"PriceList":[]}')

  # Parse prices into associative array
  declare -A PRICES
  if command -v bc &> /dev/null; then
    for itype in "${INSTANCE_TYPES[@]}"; do
      hourly=$(echo "$PRICE_DATA" | jq -r --arg type "$itype" '
        .PriceList[] |
        fromjson |
        select(.product.attributes.instanceType == $type) |
        .terms.OnDemand | to_entries[0].value.priceDimensions | to_entries[0].value.pricePerUnit.USD
      ' 2>/dev/null | head -1)

      if [[ -n "$hourly" && "$hourly" != "null" && "$hourly" != "" ]]; then
        monthly=$(echo "$hourly * 24 * 30" | bc 2>/dev/null | cut -d'.' -f1)
        [[ -n "$monthly" ]] && PRICES[$itype]="$monthly"
      fi
    done
  fi

  # Display table
  echo ""
  echo "  #   Type          vCPU   RAM    Cost/month   Use Case"
  echo "  ──────────────────────────────────────────────────────────────"

  for idx in "${!INSTANCE_TYPES[@]}"; do
    itype="${INSTANCE_TYPES[$idx]}"
    vcpu="${INSTANCE_VCPU[$idx]}"
    ram="${INSTANCE_RAM[$idx]}"
    usecase="${INSTANCE_USE[$idx]}"

    if [[ -n "${PRICES[$itype]:-}" ]]; then
      cost="\$${PRICES[$itype]}"
    else
      cost="-"
    fi

    printf "  %d)  %-13s %-6s %-6s %-12s %s\n" "$((idx + 1))" "$itype" "$vcpu" "$ram" "$cost" "$usecase"
  done

  echo ""
  read -p "Select instance size [1-6, default: 2]: " instance_choice
  case "${instance_choice:-2}" in
    1) INSTANCE_TYPE="t4g.micro" ;;
    2) INSTANCE_TYPE="t4g.small" ;;
    3) INSTANCE_TYPE="t4g.medium" ;;
    4) INSTANCE_TYPE="t4g.large" ;;
    5) INSTANCE_TYPE="t4g.xlarge" ;;
    6) INSTANCE_TYPE="t4g.2xlarge" ;;
    *) INSTANCE_TYPE="t4g.small" ;;
  esac

  # Availability Level
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Availability Level${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  #   Level    RTO        RPO        Cost       Description"
  echo "  ─────────────────────────────────────────────────────────────────────"
  echo "  1)  Low      ~1 hour    ~1 hour    +\$0        Single instance, manual recovery"
  echo "  2)  Medium   ~10 min    ~5 min     +\$5/mo     Auto Scaling Group, single AZ"
  echo "  3)  High     ~2 min     ~1 min     +\$20/mo    ASG + Multi-AZ, auto failover"
  echo ""
  read -p "Select availability level [1-3, default: 1]: " avail_choice
  case "${avail_choice:-1}" in
    1) AVAILABILITY_LEVEL="low" ;;
    2) AVAILABILITY_LEVEL="medium" ;;
    3) AVAILABILITY_LEVEL="high" ;;
    *) AVAILABILITY_LEVEL="low" ;;
  esac

  # Security Level
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Security Level${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  #   Level     Subnet    Cost       Features"
  echo "  ─────────────────────────────────────────────────────────────────────────"
  echo "  1)  Normal    Public    +\$0        SSM, encrypted EBS"
  echo "  2)  High      Public    +\$5/mo     + VPC Flow Logs, CloudTrail"
  echo "  3)  Highest   Private   +\$50/mo    + NAT Gateway, VPC Endpoints, GuardDuty"
  echo ""
  read -p "Select security level [1-3, default: 1]: " sec_choice
  case "${sec_choice:-1}" in
    1) SECURITY_LEVEL="normal" ;;
    2) SECURITY_LEVEL="high" ;;
    3) SECURITY_LEVEL="highest" ;;
    *) SECURITY_LEVEL="normal" ;;
  esac

  # Data Volume Size
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  EBS Data Volume Size${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  info "Fetching EBS gp3 pricing for region: $REGION ..."

  # Fetch EBS gp3 price per GB-month
  EBS_PRICE_PER_GB=$(aws pricing get-products \
    --service-code AmazonEC2 \
    --region us-east-1 \
    --filters \
      "Type=TERM_MATCH,Field=location,Value=$LOCATION_NAME" \
      "Type=TERM_MATCH,Field=volumeApiName,Value=gp3" \
    --output json 2>/dev/null | \
    jq -r '.PriceList[0]' 2>/dev/null | \
    jq -r '.terms.OnDemand | to_entries[0].value.priceDimensions | to_entries[0].value.pricePerUnit.USD' 2>/dev/null || echo "")

  # Volume options (size in GB)
  declare -a VOLUME_SIZES=(20 50 100 200 500 1000)
  declare -a VOLUME_DESC=("Minimal" "Standard" "Extended" "Large" "Very Large" "Maximum")

  echo ""
  echo "  #   Size      Cost/month   Use Case"
  echo "  ─────────────────────────────────────────────────────"

  for idx in "${!VOLUME_SIZES[@]}"; do
    size="${VOLUME_SIZES[$idx]}"
    desc="${VOLUME_DESC[$idx]}"

    if [[ -n "$EBS_PRICE_PER_GB" && "$EBS_PRICE_PER_GB" != "null" ]] && command -v bc &> /dev/null; then
      monthly=$(echo "$EBS_PRICE_PER_GB * $size" | bc 2>/dev/null | cut -d'.' -f1)
      [[ -z "$monthly" || "$monthly" == "0" ]] && monthly=$(echo "$EBS_PRICE_PER_GB * $size" | bc 2>/dev/null | xargs printf "%.1f" 2>/dev/null)
      cost="\$${monthly}"
    else
      cost="-"
    fi

    printf "  %d)  %-9s %-12s %s\n" "$((idx + 1))" "${size}GB" "$cost" "$desc"
  done
  echo "  7)  Custom    -            Enter custom size"

  echo ""
  read -p "Select volume size [1-7, default: 1]: " vol_choice

  case "${vol_choice:-1}" in
    1) VOLUME_SIZE=20 ;;
    2) VOLUME_SIZE=50 ;;
    3) VOLUME_SIZE=100 ;;
    4) VOLUME_SIZE=200 ;;
    5) VOLUME_SIZE=500 ;;
    6) VOLUME_SIZE=1000 ;;
    7)
      read -p "Enter custom size in GB [8-16000]: " custom_size
      if [[ "$custom_size" =~ ^[0-9]+$ ]] && [[ "$custom_size" -ge 8 ]] && [[ "$custom_size" -le 16000 ]]; then
        VOLUME_SIZE="$custom_size"
      else
        warn "Invalid size. Using default 20GB."
        VOLUME_SIZE=20
      fi
      ;;
    *) VOLUME_SIZE=20 ;;
  esac

  # Backup Frequency
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Backup Frequency${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Backups are managed via EventBridge + SSM Run Command."
  echo "  S3 bucket is always created (can enable backups later)."
  echo ""
  echo "  #   Frequency    RPO         Description"
  echo "  ─────────────────────────────────────────────────────────────────────"
  echo "  1)  None         N/A         No automatic backups"
  echo "  2)  Daily        ~24 hours   Once per day at 3:00 AM UTC"
  echo "  3)  Hourly       ~1 hour     Every hour"
  echo "  4)  5 minutes    ~5 min      Every 5 minutes (high frequency)"
  echo ""
  read -p "Select backup frequency [1-4, default: 2]: " backup_choice
  case "${backup_choice:-2}" in
    1) BACKUP_FREQUENCY="none" ;;
    2) BACKUP_FREQUENCY="daily" ;;
    3) BACKUP_FREQUENCY="hourly" ;;
    4) BACKUP_FREQUENCY="5min" ;;
    *) BACKUP_FREQUENCY="daily" ;;
  esac

  echo ""
}

#============================================================================
# Prepare Template
#============================================================================
prepare_template() {
  info "Preparing CloudFormation template..."

  # Read userdata.sh, replace placeholders, and indent for YAML
  USERDATA_CONTENT=$(cat userdata.sh | \
    sed 's/{{DATA_BUCKET}}/${DataBucket}/g' | \
    sed 's/{{AWS_REGION}}/${AWS::Region}/g')

  # Create the final template by replacing {{USERDATA}} placeholder
  # Using awk for multiline replacement
  awk -v userdata="$USERDATA_CONTENT" '
    /\{\{USERDATA\}\}/ {
      # Get the indentation from the placeholder line
      match($0, /^[[:space:]]*/)
      indent = substr($0, RSTART, RLENGTH)
      # Print each line of userdata with proper indentation
      n = split(userdata, lines, "\n")
      for (i = 1; i <= n; i++) {
        print indent lines[i]
      }
      next
    }
    { print }
  ' cfn-template.yml > cfn-template-final.yml

  success "Template prepared with embedded UserData"
}

#============================================================================
# Deploy Stack
#============================================================================
deploy_stack() {
  prepare_template

  info "Validating CloudFormation template..."
  aws cloudformation validate-template \
    --template-body file://cfn-template-final.yml \
    --region "$REGION" > /dev/null
  success "Template is valid"

  echo ""
  echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  Deployment Summary                                       ║${NC}"
  echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${YELLOW}║${NC}  Stack Name:      $STACK_NAME"
  echo -e "${YELLOW}║${NC}  Region:          $REGION"
  echo -e "${YELLOW}║${NC}  Instance Type:   $INSTANCE_TYPE"
  echo -e "${YELLOW}║${NC}  Volume Size:     ${VOLUME_SIZE}GB"
  echo -e "${YELLOW}║${NC}  Availability:    $AVAILABILITY_LEVEL"
  echo -e "${YELLOW}║${NC}  Security:        $SECURITY_LEVEL"
  echo -e "${YELLOW}║${NC}  Backup:          $BACKUP_FREQUENCY"
  echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  read -p "Proceed with deployment? [y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { info "Deployment cancelled."; exit 0; }

  echo ""
  info "Deploying CloudFormation stack..."
  aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://cfn-template-final.yml \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
      ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
      ParameterKey=DataVolumeSize,ParameterValue="$VOLUME_SIZE" \
      ParameterKey=AvailabilityLevel,ParameterValue="$AVAILABILITY_LEVEL" \
      ParameterKey=SecurityLevel,ParameterValue="$SECURITY_LEVEL" \
      ParameterKey=BackupFrequency,ParameterValue="$BACKUP_FREQUENCY"

  info "Waiting for stack creation (this may take 5-10 minutes)..."
  aws cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

  success "Stack created successfully!"
  echo ""
}

#============================================================================
# Save Configuration
#============================================================================
save_config() {
  cat > "$INSTALL_DIR/.config" << EOF
REGION=$REGION
EOF
  success "Configuration saved to $INSTALL_DIR/.config"
}

#============================================================================
# Show Results
#============================================================================
show_results() {
  ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text)

  echo ""
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                                           ║${NC}"
  echo -e "${GREEN}║   Clawdbot Deployment Complete!                           ║${NC}"
  echo -e "${GREEN}║                                                           ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BLUE}Auto Scaling Group:${NC} $ASG_NAME"
  echo ""
  echo -e "${YELLOW}Next Steps:${NC}"
  echo ""
  echo "  1. Wait a few minutes for Clawdbot to start"
  echo "  2. Access WebUI to configure API keys:"
  echo "     $INSTALL_DIR/connect.sh $STACK_NAME --port-forward"
  echo "     Then open: http://localhost:3000"
  echo ""
  echo -e "${BLUE}Commands:${NC}"
  echo ""
  echo "  # List all stacks"
  echo "  $INSTALL_DIR/list.sh"
  echo ""
  echo "  # Connect to instance"
  echo "  $INSTALL_DIR/connect.sh $STACK_NAME"
  echo ""
  echo "  # Port forward (access WebUI at localhost:3000)"
  echo "  $INSTALL_DIR/connect.sh $STACK_NAME --port-forward"
  echo ""
  echo "  # View logs"
  echo "  $INSTALL_DIR/logs.sh $STACK_NAME"
  echo ""
  echo "  # Destroy stack"
  echo "  $INSTALL_DIR/destroy.sh $STACK_NAME"
  echo ""

  # Add to PATH suggestion
  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${BLUE}Tip:${NC} Add to your shell profile for easy access:"
    echo "  echo 'export PATH=\"\$PATH:$INSTALL_DIR\"' >> ~/.bashrc"
    echo ""
  fi
}

#============================================================================
# Main
#============================================================================
main() {
  print_banner
  check_prerequisites
  download_files
  gather_parameters
  deploy_stack
  save_config
  show_results
}

main "$@"
