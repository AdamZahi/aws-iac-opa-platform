# ─────────────────────────────────────────────────────────────────────────────
# Makefile — IaC Comparison Project: CloudFormation Stack Management
#
# Usage:
#   make deploy ENV=dev REGION=eu-west-2
#   make plan   ENV=dev   (Change Set preview without apply)
#   make drift  ENV=dev
#   make destroy ENV=dev
#   make lint
#
# All targets are idempotent. Safe to re-run.
# ─────────────────────────────────────────────────────────────────────────────

# ── Defaults (override on CLI or via environment) ─────────────────────────────
ENV       ?= dev
REGION    ?= eu-west-2
PROJECT   ?= iac-comparison
BUCKET    := $(PROJECT)-cfn-templates-$(REGION)
PREFIX    := cloudformation/
STACK     := $(PROJECT)-$(ENV)-root
EXEC_ROLE := arn:aws:iam::$(shell aws sts get-caller-identity --query Account --output text 2>/dev/null):role/$(PROJECT)-$(ENV)-cfn-exec-role

# ── Template paths ─────────────────────────────────────────────────────────────
TEMPLATES := \
  network/vpc.yaml \
  iam/roles.yaml \
  security/security-groups.yaml \
  parameters/ssm-registry.yaml \
  compute/app-asg.yaml \
  root-stack.yaml

.PHONY: help lint upload validate plan deploy drift outputs destroy clean

# ── Default target ─────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  CloudFormation Stack Management — $(PROJECT)"
	@echo "  ─────────────────────────────────────────────"
	@echo "  make lint            Lint all templates with cfn-lint"
	@echo "  make upload ENV=dev  Upload templates to S3"
	@echo "  make validate        Validate templates via CloudFormation API"
	@echo "  make plan ENV=dev    Create a Change Set (dry-run)"
	@echo "  make deploy ENV=dev  Deploy / update root stack"
	@echo "  make drift ENV=dev   Detect stack drift"
	@echo "  make outputs ENV=dev Print stack outputs"
	@echo "  make destroy ENV=dev Delete the full stack (asks for confirmation)"
	@echo "  make clean           Remove local build artefacts"
	@echo ""

# ── Lint ───────────────────────────────────────────────────────────────────────
lint:
	@echo "→ Linting CloudFormation templates..."
	@cfn-lint $(TEMPLATES)
	@echo "✓ All templates passed cfn-lint"

# ── Ensure S3 bucket exists ────────────────────────────────────────────────────
.ensure-bucket:
	@aws s3api head-bucket --bucket $(BUCKET) --region $(REGION) 2>/dev/null || ( \
	  echo "→ Creating S3 bucket: $(BUCKET)" && \
	  aws s3api create-bucket \
	    --bucket $(BUCKET) \
	    --region $(REGION) \
	    --create-bucket-configuration LocationConstraint=$(REGION) && \
	  aws s3api put-bucket-versioning \
	    --bucket $(BUCKET) \
	    --versioning-configuration Status=Enabled && \
	  aws s3api put-bucket-encryption \
	    --bucket $(BUCKET) \
	    --server-side-encryption-configuration \
	      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' && \
	  aws s3api put-public-access-block \
	    --bucket $(BUCKET) \
	    --public-access-block-configuration \
	      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" && \
	  echo "✓ Bucket created and secured" \
	)

# ── Upload templates ────────────────────────────────────────────────────────────
upload: .ensure-bucket
	@echo "→ Uploading templates to s3://$(BUCKET)/$(PREFIX)..."
	@aws s3 sync . \
	  s3://$(BUCKET)/$(PREFIX) \
	  --exclude "*" \
	  --include "*.yaml" \
	  --region $(REGION)
	@echo "✓ Templates uploaded"

# ── Validate via API ────────────────────────────────────────────────────────────
validate: upload
	@echo "→ Validating templates via CloudFormation API..."
	@for tmpl in $(TEMPLATES); do \
	  dir=$$(dirname $$tmpl); \
	  file=$$(basename $$tmpl); \
	  if [ "$$dir" = "." ]; then key="$(PREFIX)$$file"; else key="$(PREFIX)$$tmpl"; fi; \
	  aws cloudformation validate-template \
	    --template-url "https://$(BUCKET).s3.$(REGION).amazonaws.com/$$key" \
	    --region $(REGION) > /dev/null && \
	  echo "  ✓ $$tmpl"; \
	done
	@echo "✓ All templates valid"

# ── Change Set (plan / dry-run) ────────────────────────────────────────────────
CHANGESET_NAME := cs-$(shell date +%Y%m%d-%H%M%S)

plan: upload
	@echo "→ Creating Change Set '$(CHANGESET_NAME)' for stack $(STACK)..."
	@aws cloudformation create-change-set \
	  --stack-name $(STACK) \
	  --template-url "https://$(BUCKET).s3.$(REGION).amazonaws.com/$(PREFIX)root-stack.yaml" \
	  --change-set-name $(CHANGESET_NAME) \
	  --change-set-type $(shell aws cloudformation describe-stacks \
	      --stack-name $(STACK) --region $(REGION) \
	      --query "Stacks[0].StackStatus" --output text 2>/dev/null \
	      | grep -q "COMPLETE\|ROLLBACK" && echo UPDATE || echo CREATE) \
	  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
	  --parameters \
	    ParameterKey=ProjectName,ParameterValue=$(PROJECT) \
	    ParameterKey=Environment,ParameterValue=$(ENV) \
	    ParameterKey=TemplatesBucketName,ParameterValue=$(BUCKET) \
	    ParameterKey=TemplatesPrefix,ParameterValue=$(PREFIX) \
	    ParameterKey=AvailabilityZone1,ParameterValue=$(REGION)a \
	    ParameterKey=AvailabilityZone2,ParameterValue=$(REGION)b \
	  --region $(REGION)
	@echo "→ Waiting for Change Set to be created..."
	@aws cloudformation wait change-set-create-complete \
	  --stack-name $(STACK) \
	  --change-set-name $(CHANGESET_NAME) \
	  --region $(REGION)
	@echo "→ Change Set contents:"
	@aws cloudformation describe-change-set \
	  --stack-name $(STACK) \
	  --change-set-name $(CHANGESET_NAME) \
	  --region $(REGION) \
	  --query "Changes[*].{Action:ResourceChange.Action,Resource:ResourceChange.LogicalResourceId,Type:ResourceChange.ResourceType}" \
	  --output table
	@echo ""
	@echo "  To apply: aws cloudformation execute-change-set \\"
	@echo "    --stack-name $(STACK) --change-set-name $(CHANGESET_NAME) --region $(REGION)"

# ── Deploy ─────────────────────────────────────────────────────────────────────
deploy: lint upload
	@echo "→ Deploying stack: $(STACK) [ENV=$(ENV) REGION=$(REGION)]"
	@aws cloudformation deploy \
	  --template-file root-stack.yaml \
	  --stack-name $(STACK) \
	  --region $(REGION) \
	  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
	  --parameter-overrides \
	    ProjectName=$(PROJECT) \
	    Environment=$(ENV) \
	    TemplatesBucketName=$(BUCKET) \
	    TemplatesPrefix=$(PREFIX) \
	    AvailabilityZone1=$(REGION)a \
	    AvailabilityZone2=$(REGION)b \
	    EnableNatGateway=true \
	    SingleNatGateway=true \
	  --no-fail-on-empty-changeset
	@$(MAKE) outputs

# ── Outputs ────────────────────────────────────────────────────────────────────
outputs:
	@echo "→ Stack outputs for $(STACK):"
	@aws cloudformation describe-stacks \
	  --stack-name $(STACK) \
	  --region $(REGION) \
	  --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]" \
	  --output table

# ── Drift Detection ────────────────────────────────────────────────────────────
drift:
	@echo "→ Initiating drift detection on $(STACK)..."
	$(eval DRIFT_ID := $(shell aws cloudformation detect-stack-drift \
	  --stack-name $(STACK) \
	  --region $(REGION) \
	  --query StackDriftDetectionId \
	  --output text))
	@echo "  Detection ID: $(DRIFT_ID)"
	@echo "→ Polling until complete (may take 1-2 minutes)..."
	@while true; do \
	  STATUS=$$(aws cloudformation describe-stack-drift-detection-status \
	    --stack-drift-detection-id $(DRIFT_ID) \
	    --region $(REGION) \
	    --query DetectionStatus --output text); \
	  echo "  Status: $$STATUS"; \
	  [ "$$STATUS" = "DETECTION_COMPLETE" ] && break; \
	  [ "$$STATUS" = "DETECTION_FAILED" ] && echo "Drift detection failed" && exit 1; \
	  sleep 10; \
	done
	@aws cloudformation describe-stack-resource-drifts \
	  --stack-name $(STACK) \
	  --region $(REGION) \
	  --stack-resource-drift-status-filters MODIFIED DELETED \
	  --query "StackResourceDrifts[*].{Resource:LogicalResourceId,Status:StackResourceDriftStatus}" \
	  --output table

# ── Destroy ────────────────────────────────────────────────────────────────────
destroy:
	@echo ""
	@echo "  ⚠️  WARNING: This will permanently delete $(STACK) and ALL nested stacks."
	@echo "  Resources: VPC, subnets, NAT GWs (EIPs), security groups, IAM roles, ASG."
	@echo ""
	@read -p "  Type the stack name to confirm deletion [$(STACK)]: " confirm; \
	  [ "$$confirm" = "$(STACK)" ] || (echo "Aborted." && exit 1)
	@echo "→ Deleting stack $(STACK)..."
	@aws cloudformation delete-stack \
	  --stack-name $(STACK) \
	  --region $(REGION)
	@aws cloudformation wait stack-delete-complete \
	  --stack-name $(STACK) \
	  --region $(REGION)
	@echo "✓ Stack deleted"

# ── Clean local artefacts ──────────────────────────────────────────────────────
clean:
	@find . -name "*.swp" -o -name ".DS_Store" | xargs rm -f
	@echo "✓ Clean"