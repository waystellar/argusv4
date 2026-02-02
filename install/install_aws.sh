#!/usr/bin/env bash
# ============================================================
# Argus Timing System — AWS Infrastructure Installer
#
# Deploys the Argus cloud stack to AWS using Terraform.
# Separate from install_cloud.sh (Docker Compose on a single server).
#
# Two deployment tiers:
#   Tier 1: Shared SaaS stack (small/medium series, cost-optimized)
#   Tier 2: Dedicated event stack (large events, high concurrency)
#
# Usage:
#   ./install/install_aws.sh                  # Interactive tier selection + apply
#   ./install/install_aws.sh --plan           # Dry-run: terraform plan only
#   ./install/install_aws.sh --tier 1         # Non-interactive: select tier 1
#   ./install/install_aws.sh --tier 2 --plan  # Dry-run tier 2
#   ./install/install_aws.sh --smoke          # Post-deploy smoke check
#   ./install/install_aws.sh --destroy        # Tear down infrastructure
#
# Required environment variables (or prompted):
#   AWS_ACCESS_KEY_ID      — AWS credentials
#   AWS_SECRET_ACCESS_KEY  — AWS credentials
#   AWS_DEFAULT_REGION     — AWS region (default: us-west-2)
#   ARGUS_DOMAIN           — Domain name (e.g. argus.example.com)
#   ARGUS_DB_PASSWORD      — PostgreSQL password
#   ARGUS_SECRET_KEY       — JWT signing key
#   ARGUS_ACM_CERT_ARN     — ACM certificate ARN (required for production domain)
#
# Optional:
#   ARGUS_AWS_CONFIG       — Path to config file with the above values
# ============================================================
set -euo pipefail

# ============ Constants ============

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/deploy/aws"
CONFIG_DIR="$PROJECT_ROOT/.argus-aws"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============ Tier Definitions ============
#
# Adjust the _FANS and _COST_* constants below to update capacity guidance
# and cost estimates everywhere in the script (selection menu, pre-apply
# summary, and final summary).  All other constants control Terraform sizing.

# Tier 1: Shared SaaS — cost-optimized for small/medium race series
TIER1_LABEL="Shared SaaS Stack"
TIER1_DESCRIPTION="Small/medium race series  |  Cost-optimized"
TIER1_FANS="~5,000"
TIER1_COST_LOW=120
TIER1_COST_HIGH=200
TIER1_ENV="prod"
TIER1_RDS_CLASS="db.t3.micro"
TIER1_RDS_STORAGE=20
TIER1_RDS_MAX_STORAGE=100
TIER1_REDIS_CLASS="cache.t3.micro"
TIER1_ECS_CPU=512
TIER1_ECS_MEMORY=1024
TIER1_ECS_DESIRED=2
TIER1_ECS_MIN=1
TIER1_ECS_MAX=6
TIER1_GUNICORN_WORKERS=2

# Tier 2: Dedicated Event — high-concurrency for large events
TIER2_LABEL="Dedicated Event Stack"
TIER2_DESCRIPTION="Large events  |  High concurrency"
TIER2_FANS="~30,000+"
TIER2_COST_LOW=350
TIER2_COST_HIGH=600
TIER2_ENV="prod"
TIER2_RDS_CLASS="db.t3.medium"
TIER2_RDS_STORAGE=50
TIER2_RDS_MAX_STORAGE=500
TIER2_REDIS_CLASS="cache.t3.medium"
TIER2_ECS_CPU=2048
TIER2_ECS_MEMORY=4096
TIER2_ECS_DESIRED=4
TIER2_ECS_MIN=2
TIER2_ECS_MAX=40
TIER2_GUNICORN_WORKERS=8

# ============ Helper Functions ============

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}>>> $1${NC}"
    echo ""
}

die() {
    log_error "$1"
    exit 1
}

# ============ Parse Arguments ============

MODE="apply"          # apply | plan | smoke | destroy
TIER=""               # 1 | 2  (empty = interactive)
AUTO_APPROVE=false
NONINTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --plan)
            MODE="plan"
            shift
            ;;
        --smoke)
            MODE="smoke"
            shift
            ;;
        --destroy)
            MODE="destroy"
            shift
            ;;
        --tier)
            TIER="$2"
            shift 2
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --noninteractive|--ci)
            NONINTERACTIVE=true
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --plan            Dry-run: run terraform init + plan only"
            echo "  --smoke           Post-deploy smoke check (validates outputs)"
            echo "  --destroy         Tear down infrastructure"
            echo "  --tier N          Select tier (1 or 2) without prompt"
            echo "  --auto-approve    Skip terraform apply confirmation"
            echo "  --noninteractive  CI mode: read all inputs from env vars, no prompts"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  AWS_ACCESS_KEY_ID       AWS credentials"
            echo "  AWS_SECRET_ACCESS_KEY   AWS credentials"
            echo "  AWS_DEFAULT_REGION      AWS region (default: us-west-2)"
            echo "  ARGUS_TIER              Deployment tier: 1 or 2 (CI alternative to --tier)"
            echo "  ARGUS_DOMAIN            Domain name (e.g. argus.example.com)"
            echo "  ARGUS_DB_PASSWORD       PostgreSQL password (auto-generated if empty)"
            echo "  ARGUS_SECRET_KEY        JWT signing key (auto-generated if empty)"
            echo "  ARGUS_ACM_CERT_ARN      ACM certificate ARN (optional)"
            echo "  ARGUS_AWS_CONFIG        Path to config file with above values"
            echo ""
            echo "CI Example:"
            echo "  export AWS_ACCESS_KEY_ID=AKIA..."
            echo "  export AWS_SECRET_ACCESS_KEY=..."
            echo "  export ARGUS_DOMAIN=argus.example.com"
            echo "  export ARGUS_TIER=1"
            echo "  $0 --noninteractive"
            exit 0
            ;;
        *)
            die "Unknown option: $1 (use --help for usage)"
            ;;
    esac
done

# Resolve tier from env var if not set via flag
if [ -z "$TIER" ] && [ -n "${ARGUS_TIER:-}" ]; then
    TIER="$ARGUS_TIER"
fi

# ============ Banner ============

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║           ARGUS TIMING SYSTEM — AWS INSTALLER                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ============ Prerequisite Checks ============

check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=0

    # Terraform
    if command -v terraform >/dev/null 2>&1; then
        local tf_version
        tf_version=$(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || terraform version | head -1)
        log_success "Terraform installed: $tf_version"
    else
        log_error "Terraform not found. Install from https://developer.hashicorp.com/terraform/install"
        missing=1
    fi

    # AWS CLI
    if command -v aws >/dev/null 2>&1; then
        local aws_version
        aws_version=$(aws --version 2>&1 | head -1)
        log_success "AWS CLI installed: $aws_version"
    else
        log_error "AWS CLI not found. Install from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        missing=1
    fi

    # jq (used for output parsing)
    if command -v jq >/dev/null 2>&1; then
        log_success "jq installed"
    else
        log_warn "jq not found — smoke check will use python3 fallback"
    fi

    # python3 (for JSON parsing fallback)
    if command -v python3 >/dev/null 2>&1; then
        log_success "python3 installed"
    else
        log_error "python3 not found (required for config parsing)"
        missing=1
    fi

    # Terraform directory exists
    if [ -d "$TF_DIR" ]; then
        log_success "Terraform config found at deploy/aws/"
    else
        die "Terraform directory not found: $TF_DIR"
    fi

    if [ "$missing" -gt 0 ]; then
        die "Missing prerequisites. Install the tools above and retry."
    fi
}

# ============ AWS Credentials ============

check_aws_credentials() {
    log_step "Checking AWS credentials"

    # Load config file if specified
    if [ -n "${ARGUS_AWS_CONFIG:-}" ] && [ -f "$ARGUS_AWS_CONFIG" ]; then
        log_info "Loading config from $ARGUS_AWS_CONFIG"
        # shellcheck source=/dev/null
        source "$ARGUS_AWS_CONFIG"
    fi

    # Check AWS credentials: env vars > AWS_PROFILE > ~/.aws/credentials > instance role
    local cred_source=""
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
        cred_source="environment variables"
    elif [ -n "${AWS_PROFILE:-}" ]; then
        cred_source="AWS_PROFILE=$AWS_PROFILE"
    elif [ -f "${HOME}/.aws/credentials" ]; then
        cred_source="~/.aws/credentials"
    fi

    if aws sts get-caller-identity >/dev/null 2>&1; then
        local account_id
        account_id=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "unknown")
        log_success "AWS credentials valid (account: $account_id, source: ${cred_source:-instance role / SSO})"
    else
        echo ""
        log_error "No valid AWS credentials found."
        echo ""
        echo "  Set credentials via one of:"
        echo "    export AWS_ACCESS_KEY_ID=AKIA..."
        echo "    export AWS_SECRET_ACCESS_KEY=..."
        echo ""
        echo "    export AWS_PROFILE=my-profile"
        echo ""
        echo "    aws configure              # writes to ~/.aws/credentials"
        echo ""
        echo "    Or create a config file and pass via:"
        echo "    ARGUS_AWS_CONFIG=./aws.env $0"
        echo ""
        die "AWS credentials are required."
    fi
}

# ============ Tier Selection ============

select_tier() {
    log_step "Deployment Tier Selection"

    if [ -n "$TIER" ]; then
        if [ "$TIER" != "1" ] && [ "$TIER" != "2" ]; then
            die "Invalid tier: $TIER (must be 1 or 2)"
        fi
        log_info "Tier $TIER selected via --tier / ARGUS_TIER"
    elif [ "$NONINTERACTIVE" = true ]; then
        die "Tier is required in --noninteractive mode. Set --tier N or export ARGUS_TIER=1|2"
    else
        echo -e "${BOLD}Choose a deployment tier:${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC} ${BOLD}$TIER1_LABEL${NC}"
        echo -e "      ${DIM}${TIER1_DESCRIPTION}${NC}"
        echo -e "      Capacity: ${TIER1_FANS} concurrent fans"
        echo -e "      ECS: ${TIER1_ECS_MIN}–${TIER1_ECS_MAX} tasks (${TIER1_ECS_CPU} CPU / ${TIER1_ECS_MEMORY} MB each)"
        echo -e "      RDS: ${TIER1_RDS_CLASS} (${TIER1_RDS_STORAGE}–${TIER1_RDS_MAX_STORAGE} GB)"
        echo -e "      Redis: ${TIER1_REDIS_CLASS}"
        echo -e "      Est. cost: ${GREEN}\$${TIER1_COST_LOW}–\$${TIER1_COST_HIGH}/mo${NC} (on-demand, before data transfer)"
        echo ""
        echo -e "  ${CYAN}[2]${NC} ${BOLD}$TIER2_LABEL${NC}"
        echo -e "      ${DIM}${TIER2_DESCRIPTION}${NC}"
        echo -e "      Capacity: ${TIER2_FANS} concurrent fans"
        echo -e "      ECS: ${TIER2_ECS_MIN}–${TIER2_ECS_MAX} tasks (${TIER2_ECS_CPU} CPU / ${TIER2_ECS_MEMORY} MB each)"
        echo -e "      RDS: ${TIER2_RDS_CLASS} (${TIER2_RDS_STORAGE}–${TIER2_RDS_MAX_STORAGE} GB)"
        echo -e "      Redis: ${TIER2_REDIS_CLASS}"
        echo -e "      Est. cost: ${YELLOW}\$${TIER2_COST_LOW}–\$${TIER2_COST_HIGH}/mo${NC} (on-demand, before data transfer)"
        echo ""

        while true; do
            read -rp "  Select tier [1/2]: " TIER
            if [ "$TIER" = "1" ] || [ "$TIER" = "2" ]; then
                break
            fi
            echo "  Please enter 1 or 2."
        done
    fi

    echo ""
    if [ "$TIER" = "1" ]; then
        echo -e "  ${GREEN}Selected: Tier 1 — $TIER1_LABEL${NC}"
        echo -e "  Supports ${TIER1_FANS} concurrent fans"
        echo -e "  Est. cost: \$${TIER1_COST_LOW}–\$${TIER1_COST_HIGH}/mo"
    else
        echo -e "  ${GREEN}Selected: Tier 2 — $TIER2_LABEL${NC}"
        echo -e "  Supports ${TIER2_FANS} concurrent fans"
        echo -e "  Est. cost: \$${TIER2_COST_LOW}–\$${TIER2_COST_HIGH}/mo"
    fi
    echo ""
}

# ============ Pre-Apply Tier Summary ============

print_pre_apply_summary() {
    # Shown after plan, before apply — always visible regardless of how tier was chosen.
    local label desc fans cost_lo cost_hi cost_color
    local rds redis ecs_cpu ecs_mem ecs_min ecs_max workers

    if [ "$TIER" = "1" ]; then
        label="$TIER1_LABEL";        desc="$TIER1_DESCRIPTION"
        fans="$TIER1_FANS";          cost_lo="$TIER1_COST_LOW"; cost_hi="$TIER1_COST_HIGH"
        cost_color="$GREEN"
        rds="$TIER1_RDS_CLASS";      redis="$TIER1_REDIS_CLASS"
        ecs_cpu="$TIER1_ECS_CPU";    ecs_mem="$TIER1_ECS_MEMORY"
        ecs_min="$TIER1_ECS_MIN";    ecs_max="$TIER1_ECS_MAX"
        workers="$TIER1_GUNICORN_WORKERS"
    else
        label="$TIER2_LABEL";        desc="$TIER2_DESCRIPTION"
        fans="$TIER2_FANS";          cost_lo="$TIER2_COST_LOW"; cost_hi="$TIER2_COST_HIGH"
        cost_color="$YELLOW"
        rds="$TIER2_RDS_CLASS";      redis="$TIER2_REDIS_CLASS"
        ecs_cpu="$TIER2_ECS_CPU";    ecs_mem="$TIER2_ECS_MEMORY"
        ecs_min="$TIER2_ECS_MIN";    ecs_max="$TIER2_ECS_MAX"
        workers="$TIER2_GUNICORN_WORKERS"
    fi

    log_step "Deployment Summary — Tier $TIER"

    echo -e "  ${BOLD}${label}${NC}  ${DIM}(${desc})${NC}"
    echo ""
    echo -e "  ${BOLD}Capacity${NC}"
    echo "  Concurrent fans:  ${fans}"
    echo "  ECS tasks:        ${ecs_min}–${ecs_max} (${ecs_cpu} CPU / ${ecs_mem} MB each)"
    echo "  Gunicorn workers: ${workers} per task"
    echo ""
    echo -e "  ${BOLD}Infrastructure${NC}"
    echo "  RDS:     ${rds}"
    echo "  Redis:   ${redis}"
    echo "  Region:  ${AWS_DEFAULT_REGION}"
    echo "  Domain:  ${ARGUS_DOMAIN}"
    echo ""
    echo -e "  ${BOLD}Estimated Cost${NC}"
    echo -e "  ${cost_color}\$${cost_lo}–\$${cost_hi}/mo${NC} (on-demand, before data transfer)"

    if [ "$TIER" = "2" ]; then
        echo ""
        echo -e "  ${YELLOW}NOTE:${NC} Tier 2 uses higher autoscaling limits (up to ${ecs_max} ECS tasks)"
        echo -e "  and larger backing services. Actual cost scales with traffic and"
        echo -e "  will be higher during peak events when autoscaling is active."
    fi

    echo ""
}

# ============ Collect Required Inputs ============

collect_inputs() {
    log_step "Configuration"

    # Region — allow interactive override of the default
    if [ "$NONINTERACTIVE" = true ]; then
        export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
    else
        local current_region="${AWS_DEFAULT_REGION:-us-west-2}"
        read -rp "  AWS region [${current_region}]: " input_region
        export AWS_DEFAULT_REGION="${input_region:-$current_region}"
    fi
    log_info "Region: $AWS_DEFAULT_REGION"

    # Domain
    if [ -z "${ARGUS_DOMAIN:-}" ]; then
        if [ "$NONINTERACTIVE" = true ]; then
            die "ARGUS_DOMAIN is required in --noninteractive mode."
        fi
        read -rp "  Domain name (e.g. argus.example.com): " ARGUS_DOMAIN
        if [ -z "$ARGUS_DOMAIN" ]; then
            die "Domain name is required."
        fi
    fi
    log_info "Domain: $ARGUS_DOMAIN"

    # Database password — auto-generate if missing (safe for CI)
    if [ -z "${ARGUS_DB_PASSWORD:-}" ]; then
        ARGUS_DB_PASSWORD=$(openssl rand -hex 20 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(20))")
        log_info "Database password auto-generated (saved to config)"
    else
        log_info "Database password provided via env"
    fi

    # Secret key — auto-generate if missing (safe for CI)
    if [ -z "${ARGUS_SECRET_KEY:-}" ]; then
        ARGUS_SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
        log_info "JWT secret key auto-generated (saved to config)"
    else
        log_info "JWT secret key provided via env"
    fi

    # ACM certificate ARN
    if [ -z "${ARGUS_ACM_CERT_ARN:-}" ]; then
        if [ "$NONINTERACTIVE" = true ]; then
            ARGUS_ACM_CERT_ARN=""
            log_warn "No ACM certificate (ARGUS_ACM_CERT_ARN not set) — CloudFront will use default domain"
        else
            echo ""
            echo -e "  ${YELLOW}ACM Certificate:${NC}"
            echo "  An ACM certificate in us-east-1 is required for CloudFront HTTPS."
            echo "  Create one at: https://console.aws.amazon.com/acm/home?region=us-east-1"
            echo "  It must cover: $ARGUS_DOMAIN"
            echo ""
            read -rp "  ACM Certificate ARN (or press Enter to skip for now): " ARGUS_ACM_CERT_ARN
            if [ -z "$ARGUS_ACM_CERT_ARN" ]; then
                log_warn "No ACM certificate — CloudFront will use default domain (no custom HTTPS domain)"
            fi
        fi
    else
        log_info "ACM certificate: $ARGUS_ACM_CERT_ARN"
    fi

    # Save config for reproducibility
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.env" << ENVEOF
# Argus AWS Deployment Config
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Tier: $TIER
ARGUS_TIER="$TIER"
ARGUS_DOMAIN="$ARGUS_DOMAIN"
ARGUS_DB_PASSWORD="$ARGUS_DB_PASSWORD"
ARGUS_SECRET_KEY="$ARGUS_SECRET_KEY"
ARGUS_ACM_CERT_ARN="${ARGUS_ACM_CERT_ARN:-}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}"
ENVEOF
    chmod 600 "$CONFIG_DIR/config.env"
    log_success "Config saved to .argus-aws/config.env"
}

# ============ Generate Terraform Variables ============

generate_tfvars() {
    log_step "Generating Terraform variables"

    local tfvars_file="$CONFIG_DIR/tier${TIER}.tfvars"

    local tier_tf_value
    if [ "$TIER" = "1" ]; then tier_tf_value="tier1"; else tier_tf_value="tier2"; fi

    if [ "$TIER" = "1" ]; then
        cat > "$tfvars_file" << TFEOF
# Argus AWS — Tier 1: Shared SaaS Stack
# Auto-generated by install_aws.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# General
project_name    = "argus"
environment     = "${TIER1_ENV}"
aws_region      = "${AWS_DEFAULT_REGION}"
domain_name     = "${ARGUS_DOMAIN}"
deployment_tier = "${tier_tf_value}"

# Database
db_name     = "argus"
db_username = "argus"
db_password = "${ARGUS_DB_PASSWORD}"

# Security
secret_key = "${ARGUS_SECRET_KEY}"

# SSL Certificate
acm_certificate_arn = "${ARGUS_ACM_CERT_ARN:-}"

# RDS — Tier 1: cost-optimized
rds_instance_class    = "${TIER1_RDS_CLASS}"
rds_allocated_storage = ${TIER1_RDS_STORAGE}
rds_max_storage       = ${TIER1_RDS_MAX_STORAGE}

# Redis — Tier 1: cost-optimized
redis_node_type = "${TIER1_REDIS_CLASS}"

# ECS — Tier 1: moderate scaling
ecs_cpu           = ${TIER1_ECS_CPU}
ecs_memory        = ${TIER1_ECS_MEMORY}
ecs_desired_count = ${TIER1_ECS_DESIRED}
ecs_min_count     = ${TIER1_ECS_MIN}
ecs_max_count     = ${TIER1_ECS_MAX}
gunicorn_workers  = ${TIER1_GUNICORN_WORKERS}
TFEOF
    else
        cat > "$tfvars_file" << TFEOF
# Argus AWS — Tier 2: Dedicated Event Stack
# Auto-generated by install_aws.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# General
project_name    = "argus"
environment     = "${TIER2_ENV}"
aws_region      = "${AWS_DEFAULT_REGION}"
domain_name     = "${ARGUS_DOMAIN}"
deployment_tier = "${tier_tf_value}"

# Database
db_name     = "argus"
db_username = "argus"
db_password = "${ARGUS_DB_PASSWORD}"

# Security
secret_key = "${ARGUS_SECRET_KEY}"

# SSL Certificate
acm_certificate_arn = "${ARGUS_ACM_CERT_ARN:-}"

# RDS — Tier 2: high-throughput
rds_instance_class    = "${TIER2_RDS_CLASS}"
rds_allocated_storage = ${TIER2_RDS_STORAGE}
rds_max_storage       = ${TIER2_RDS_MAX_STORAGE}

# Redis — Tier 2: high-throughput
redis_node_type = "${TIER2_REDIS_CLASS}"

# ECS — Tier 2: high-concurrency scaling
ecs_cpu           = ${TIER2_ECS_CPU}
ecs_memory        = ${TIER2_ECS_MEMORY}
ecs_desired_count = ${TIER2_ECS_DESIRED}
ecs_min_count     = ${TIER2_ECS_MIN}
ecs_max_count     = ${TIER2_ECS_MAX}
gunicorn_workers  = ${TIER2_GUNICORN_WORKERS}
TFEOF
    fi

    chmod 600 "$tfvars_file"
    log_success "Generated $tfvars_file"
}

# ============ Terraform Init ============

terraform_init() {
    log_step "Terraform Init"

    cd "$TF_DIR"

    terraform init -input=false
    log_success "Terraform initialized"

    # Select or create workspace for this tier
    local workspace="tier${TIER}"

    if terraform workspace list 2>/dev/null | grep -q "$workspace"; then
        terraform workspace select "$workspace"
        log_success "Selected workspace: $workspace"
    else
        terraform workspace new "$workspace"
        log_success "Created workspace: $workspace"
    fi
}

# ============ Terraform Plan ============

terraform_plan() {
    log_step "Terraform Plan"

    local tfvars_file="$CONFIG_DIR/tier${TIER}.tfvars"

    cd "$TF_DIR"

    terraform plan \
        -var-file="$tfvars_file" \
        -out="$CONFIG_DIR/tier${TIER}.tfplan" \
        -input=false

    log_success "Plan saved to .argus-aws/tier${TIER}.tfplan"
}

# ============ Terraform Apply ============

terraform_apply() {
    log_step "Terraform Apply"

    cd "$TF_DIR"

    local plan_file="$CONFIG_DIR/tier${TIER}.tfplan"

    if [ -f "$plan_file" ]; then
        # Plan files are always applied without confirmation prompt (Terraform behavior).
        # The plan itself was reviewed during the plan step.
        terraform apply "$plan_file"
    else
        # No plan file — apply directly from tfvars (fallback)
        local tfvars_file="$CONFIG_DIR/tier${TIER}.tfvars"
        local approve_flag=""
        if [ "$AUTO_APPROVE" = true ]; then
            approve_flag="-auto-approve"
        fi
        # shellcheck disable=SC2086
        terraform apply -var-file="$tfvars_file" -input=false $approve_flag
    fi

    log_success "Infrastructure deployed"

    # Save outputs for reference
    terraform output -json > "$CONFIG_DIR/tier${TIER}-outputs.json" 2>/dev/null || true
    log_success "Outputs saved to .argus-aws/tier${TIER}-outputs.json"
}

# ============ Terraform Destroy ============

terraform_destroy() {
    log_step "Terraform Destroy"

    local tfvars_file="$CONFIG_DIR/tier${TIER}.tfvars"

    if [ ! -f "$tfvars_file" ]; then
        die "No config found for tier $TIER. Nothing to destroy."
    fi

    echo -e "${RED}${BOLD}WARNING: This will DESTROY all Argus AWS infrastructure for Tier $TIER.${NC}"
    echo ""
    echo "  This includes: VPC, RDS database, Redis, ECS cluster, ALB, CloudFront, S3 bucket."
    echo "  Data in RDS and S3 will be PERMANENTLY LOST."
    echo ""

    if [ "$AUTO_APPROVE" != true ]; then
        read -rp "  Type 'destroy' to confirm: " confirm
        if [ "$confirm" != "destroy" ]; then
            echo "  Cancelled."
            exit 0
        fi
    fi

    cd "$TF_DIR"

    local workspace="tier${TIER}"
    if terraform workspace list 2>/dev/null | grep -q "$workspace"; then
        terraform workspace select "$workspace"
    else
        die "Workspace $workspace does not exist."
    fi

    terraform destroy \
        -var-file="$tfvars_file" \
        -auto-approve

    log_success "Infrastructure destroyed"
}

# ============ Post-Deploy: DNS Hints ============

print_dns_hints() {
    log_step "DNS Configuration"

    local outputs_file="$CONFIG_DIR/tier${TIER}-outputs.json"

    if [ ! -f "$outputs_file" ]; then
        log_warn "No outputs file — run apply first"
        return
    fi

    local cf_domain alb_dns alb_zone_id
    cf_domain=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('cloudfront_domain_name',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    alb_dns=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('alb_dns_name',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    alb_zone_id=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('alb_zone_id',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")

    echo "  Add these DNS records to your domain registrar:"
    echo ""
    echo -e "  ${BOLD}Option A: CloudFront (recommended for web + API)${NC}"
    echo "  Type:  CNAME"
    echo "  Name:  ${ARGUS_DOMAIN}"
    echo "  Value: ${cf_domain}"
    echo ""
    echo -e "  ${BOLD}Option B: ALB direct (API only, for testing)${NC}"
    echo "  Type:  CNAME"
    echo "  Name:  api.${ARGUS_DOMAIN}"
    echo "  Value: ${alb_dns}"
    echo ""
    echo -e "  ${DIM}If using Route53, create an Alias record pointing to CloudFront.${NC}"
    echo -e "  ${DIM}ALB Zone ID (for Route53 alias): ${alb_zone_id}${NC}"
    echo ""
}

# ============ Post-Deploy: Deployment Instructions ============

print_deploy_instructions() {
    log_step "Next Steps: Deploy Application"

    local outputs_file="$CONFIG_DIR/tier${TIER}-outputs.json"

    if [ ! -f "$outputs_file" ]; then
        return
    fi

    local ecr_url cluster_name service_name web_bucket cf_dist_id
    ecr_url=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('ecr_repository_url',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    cluster_name=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('ecs_cluster_name',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    service_name=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('ecs_service_name',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    web_bucket=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('web_bucket_name',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
    cf_dist_id=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('cloudfront_distribution_id',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")

    echo "  1. Build and push API container:"
    echo ""
    echo -e "     ${DIM}aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \\"
    echo "       docker login --username AWS --password-stdin ${ecr_url%%/*}"
    echo "     docker build -t argus-api ./cloud"
    echo "     docker tag argus-api:latest ${ecr_url}:latest"
    echo -e "     docker push ${ecr_url}:latest${NC}"
    echo ""
    echo "  2. Update ECS service:"
    echo ""
    echo -e "     ${DIM}aws ecs update-service --cluster ${cluster_name} \\"
    echo -e "       --service ${service_name} --force-new-deployment${NC}"
    echo ""
    echo "  3. Deploy web frontend:"
    echo ""
    echo -e "     ${DIM}cd web && npm run build"
    echo "     aws s3 sync dist/ s3://${web_bucket} --delete"
    echo -e "     aws cloudfront create-invalidation --distribution-id ${cf_dist_id} --paths '/*'${NC}"
    echo ""
}

# ============ Smoke Check ============

smoke_check() {
    log_step "Post-Deploy Smoke Check"

    local outputs_file="$CONFIG_DIR/tier${TIER}-outputs.json"
    local pass=0
    local fail=0

    if [ ! -f "$outputs_file" ]; then
        die "No outputs file found. Run apply first: $0 --tier $TIER"
    fi

    echo "  Validating Terraform outputs..."
    echo ""

    # Required outputs — includes tier-aware outputs added in deploy/aws/outputs.tf
    local required_outputs=(
        "vpc_id"
        "rds_endpoint"
        "redis_endpoint"
        "ecs_cluster_name"
        "ecs_service_name"
        "ecr_repository_url"
        "alb_dns_name"
        "cloudfront_domain_name"
        "web_bucket_name"
        "cloudfront_distribution_id"
        "deployment_tier"
        "effective_sizing"
    )

    for key in "${required_outputs[@]}"; do
        local value
        value=$(python3 -c "
import json, sys
d = json.load(open('$outputs_file'))
v = d.get('$key', {}).get('value', '')
print(v if v else '')
" 2>/dev/null || echo "")

        if [ -n "$value" ] && [ "$value" != "None" ]; then
            echo -e "  ${GREEN}OK${NC}  $key = $value"
            ((pass++))
        else
            echo -e "  ${RED}MISSING${NC}  $key"
            ((fail++))
        fi
    done

    echo ""

    # Try to reach the ALB health endpoint
    local alb_dns
    alb_dns=$(python3 -c "import json; print(json.load(open('$outputs_file')).get('alb_dns_name',{}).get('value',''))" 2>/dev/null || echo "")

    if [ -n "$alb_dns" ]; then
        echo "  Checking ALB health endpoint..."
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${alb_dns}/health" 2>/dev/null || echo "000")

        if [ "$http_code" = "200" ]; then
            echo -e "  ${GREEN}OK${NC}  ALB /health returned HTTP 200"
            ((pass++))
        elif [ "$http_code" = "000" ]; then
            echo -e "  ${YELLOW}SKIP${NC}  ALB not reachable yet (container may not be deployed)"
        else
            echo -e "  ${YELLOW}INFO${NC}  ALB /health returned HTTP $http_code"
        fi
    fi

    # Check CloudFront
    local cf_domain
    cf_domain=$(python3 -c "import json; print(json.load(open('$outputs_file')).get('cloudfront_domain_name',{}).get('value',''))" 2>/dev/null || echo "")

    if [ -n "$cf_domain" ]; then
        echo "  Checking CloudFront..."
        local cf_code
        cf_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://${cf_domain}" 2>/dev/null || echo "000")

        if [ "$cf_code" = "200" ] || [ "$cf_code" = "403" ]; then
            echo -e "  ${GREEN}OK${NC}  CloudFront reachable (HTTP $cf_code)"
            ((pass++))
        elif [ "$cf_code" = "000" ]; then
            echo -e "  ${YELLOW}SKIP${NC}  CloudFront not reachable yet (distribution may be deploying)"
        else
            echo -e "  ${YELLOW}INFO${NC}  CloudFront returned HTTP $cf_code"
        fi
    fi

    echo ""
    echo "  ================================================"
    echo "  Results: $pass passed, $fail failed"
    echo "  ================================================"

    if [ "$fail" -gt 0 ]; then
        exit 1
    fi
}

# ============ Summary ============

print_summary() {
    local tier_label
    if [ "$TIER" = "1" ]; then
        tier_label="$TIER1_LABEL"
    else
        tier_label="$TIER2_LABEL"
    fi

    local outputs_file="$CONFIG_DIR/tier${TIER}-outputs.json"

    # Extract endpoints from Terraform outputs
    local api_url cf_url cf_domain alb_dns ssm_path
    api_url="<pending>"
    cf_url="<pending>"
    cf_domain=""
    alb_dns=""
    ssm_path="/${ARGUS_DOMAIN%%.*}/${TIER1_ENV}/secret_key"

    if [ -f "$outputs_file" ]; then
        api_url=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('api_url',{}).get('value','<pending>'))" 2>/dev/null || echo "<pending>")
        cf_domain=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('cloudfront_domain_name',{}).get('value',''))" 2>/dev/null || echo "")
        alb_dns=$(python3 -c "import json; d=json.load(open('$outputs_file')); print(d.get('alb_dns_name',{}).get('value',''))" 2>/dev/null || echo "")
        if [ -n "$cf_domain" ]; then
            cf_url="https://${cf_domain}"
        fi
    fi

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ARGUS AWS DEPLOYMENT COMPLETE                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Deployment${NC}"
    echo "  Tier:        $TIER — $tier_label"
    echo "  Workspace:   tier${TIER}"
    echo "  Region:      ${AWS_DEFAULT_REGION}"
    echo "  Domain:      ${ARGUS_DOMAIN}"
    echo ""
    echo -e "  ${BOLD}Endpoints${NC}"
    echo "  API:         ${api_url}"
    echo "  CloudFront:  ${cf_url}"
    if [ -n "$alb_dns" ]; then
        echo "  ALB direct:  https://${alb_dns}"
    fi
    echo ""
    echo -e "  ${BOLD}Secrets${NC}"
    echo "  JWT key:     AWS SSM Parameter Store (/argus/prod/secret_key)"
    echo "  DB password: .argus-aws/config.env (chmod 600)"
    echo "  Config:      .argus-aws/config.env"
    echo "  Outputs:     .argus-aws/tier${TIER}-outputs.json"
    echo ""
    echo -e "  ${BOLD}Next commands${NC}"
    echo "  Smoke check: $0 --tier $TIER --smoke"
    echo "  Tear down:   $0 --tier $TIER --destroy"
    echo ""
}

# ============ Main ============

main() {
    print_banner

    # ---- Smoke mode: skip everything except the check ----
    if [ "$MODE" = "smoke" ]; then
        if [ -z "$TIER" ]; then
            die "--tier is required for smoke check (e.g. --tier 1 --smoke)"
        fi
        smoke_check
        exit 0
    fi

    # ---- Prerequisites ----
    check_prerequisites
    check_aws_credentials

    # ---- Tier selection ----
    select_tier

    # ---- Destroy mode ----
    if [ "$MODE" = "destroy" ]; then
        # Load saved config if present
        if [ -f "$CONFIG_DIR/config.env" ]; then
            # shellcheck source=/dev/null
            source "$CONFIG_DIR/config.env"
        fi
        terraform_init
        terraform_destroy
        exit 0
    fi

    # ---- Collect inputs ----
    collect_inputs

    # ---- Generate tfvars ----
    generate_tfvars

    # ---- Terraform init ----
    terraform_init

    # ---- Terraform plan ----
    terraform_plan

    # ---- Pre-apply tier summary (always shown) ----
    print_pre_apply_summary

    # ---- Plan-only mode: stop here ----
    if [ "$MODE" = "plan" ]; then
        echo ""
        log_success "Dry-run complete. Review the plan above."
        echo ""
        echo "  To apply:  $0 --tier $TIER"
        echo "  Plan file: .argus-aws/tier${TIER}.tfplan"
        exit 0
    fi

    # ---- Terraform apply (zero-touch from here) ----
    terraform_apply

    # ---- Post-deploy info ----
    print_dns_hints
    print_deploy_instructions

    # ---- Smoke check ----
    smoke_check

    # ---- Done ----
    print_summary
}

main "$@"
