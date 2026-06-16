#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Upload CFN templates to S3 and deploy / update the root stack
#
# Usage:
#   ./deploy.sh [ENVIRONMENT] [AWS_REGION]
#
# Examples:
#   ./deploy.sh dev eu-west-2
#   ./deploy.sh prod us-east-1
#
# Prerequisites: AWS CLI v2, credentials configured (env vars or ~/.aws).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ────────────────────────────────────────────────────
ENVIRONMENT="${1:-dev}"
AWS_REGION="${2:-eu-west-2}"
PROJECT_NAME="iac-comparison"
BUCKET_NAME="${PROJECT_NAME}-cfn-templates-${AWS_REGION}"
TEMPLATES_PREFIX="cloudformation/"
STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-root"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. Ensure the S3 bucket exists ───────────────────────────
info "Ensuring S3 bucket: ${BUCKET_NAME}"
if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  info "Creating bucket ${BUCKET_NAME}..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  info "Bucket created and secured."
else
  info "Bucket already exists."
fi

# ── 2. Upload templates ───────────────────────────────────────
info "Uploading CloudFormation templates to s3://${BUCKET_NAME}/${TEMPLATES_PREFIX}"
aws s3 sync "${SCRIPT_DIR}/" \
  "s3://${BUCKET_NAME}/${TEMPLATES_PREFIX}" \
  --exclude "*" \
  --include "*.yaml" \
  --region "${AWS_REGION}"
info "Templates uploaded."

# ── 3. Validate templates ─────────────────────────────────────
info "Validating templates..."
for tmpl in "${SCRIPT_DIR}/network/vpc.yaml" \
             "${SCRIPT_DIR}/security/security-groups.yaml" \
             "${SCRIPT_DIR}/root-stack.yaml"; do
  aws cloudformation validate-template \
    --template-url "https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/${TEMPLATES_PREFIX}$(basename $(dirname ${tmpl}))/$(basename ${tmpl})" \
    --region "${AWS_REGION}" > /dev/null
  info "  ✓ $(basename ${tmpl})"
done

# ── 4. Deploy / update root stack ────────────────────────────
info "Deploying stack: ${STACK_NAME}"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/root-stack.yaml" \
  --stack-name "${STACK_NAME}" \
  --region "${AWS_REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ProjectName="${PROJECT_NAME}" \
    Environment="${ENVIRONMENT}" \
    TemplatesBucketName="${BUCKET_NAME}" \
    TemplatesPrefix="${TEMPLATES_PREFIX}" \
    AvailabilityZone1="${AWS_REGION}a" \
    AvailabilityZone2="${AWS_REGION}b" \
    EnableNatGateway="true" \
    SingleNatGateway="true" \
  --no-fail-on-empty-changeset

info "Stack deployed successfully."

# ── 5. Print outputs ─────────────────────────────────────────
info "Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${AWS_REGION}" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table