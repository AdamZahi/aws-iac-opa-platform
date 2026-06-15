# Terraform Backend Setup in AWS

## Overview

The Terraform backend is the mechanism by which Terraform stores its **state files** (the source of truth for your infrastructure). This project uses **AWS S3 + DynamoDB** for remote state management, providing security, durability, and team collaboration capabilities.

---

## What is a Terraform Backend?

### Local vs Remote Backends

**Local Backend (Default):**
- State stored in `terraform.tfstate` on your local machine
- Not suitable for team collaboration
- Risk of accidental deletion
- No version control or audit trail
- No locking (concurrent operations can corrupt state)

**Remote Backend (AWS S3):**
- State stored in centralized AWS S3 bucket
- Shared across team members
- Durable and backed up
- Version control and audit trails
- State locking via DynamoDB prevents concurrent modifications
- Encryption at rest and in transit

---

## Architecture: S3 + DynamoDB Backend

### Why S3 + DynamoDB?

```
┌──────────────────────────────────────────────┐
│          Terraform Workflow                   │
├──────────────────────────────────────────────┤
│  1. Run: terraform init/plan/apply            │
│  2. Read/Write State                          │
│  3. Lock State (prevent concurrent access)    │
│  4. Execute Infrastructure Changes            │
│  5. Store Updated State                       │
└──────────────────────────────────────────────┘
         │
         ├─────────────────┬────────────────────┐
         │                 │                    │
         ▼                 ▼                    ▼
    ┌─────────┐      ┌─────────────┐      ┌──────────┐
    │    S3   │      │  DynamoDB   │      │   AWS    │
    │ Bucket  │      │   Table     │      │  IAM     │
    │ (State) │      │  (Locks)    │      │(Authz)   │
    └─────────┘      └─────────────┘      └──────────┘
```

**S3 Bucket (`terraform-iac-project-state`):**
- Stores actual state files (dev, staging, prod)
- Versioning enabled for rollback capability
- Encryption at rest (AES-256)
- MFA delete protection (optional, recommended)

**DynamoDB Table (`terraform-locks`):**
- Stores lock information during operations
- Prevents race conditions and concurrent modifications
- Primary key: `LockID` (unique identifier per state file)
- Automatically cleans up expired locks

**IAM Roles/Policies:**
- Controls who can read/write state
- Enforces least-privilege access
- Audit trails via CloudTrail

---

## Current Backend Configuration

### Backend Definition (Per-Environment)

Each environment has identical backend configuration in `backend.tf`:

**File:** `environments/{dev|staging|prod}/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-iac-project-state"
    key            = "dev/terraform.tfstate"              # Different per environment
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### State File Organization

```
S3 Bucket: terraform-iac-project-state/
├── dev/
│   └── terraform.tfstate            (1.2 KB)
├── staging/
│   └── terraform.tfstate            (1.2 KB)
└── prod/
    └── terraform.tfstate            (1.2 KB)
```

**Key Design Decisions:**

| Aspect | Value | Rationale |
|--------|-------|-----------|
| Bucket Name | `terraform-iac-project-state` | Globally unique, descriptive |
| Region | `eu-west-2` | Matches infrastructure region |
| Encryption | `true` | SSE-S3 encryption for sensitive data |
| DynamoDB Table | `terraform-locks` | Centralized locking (shared across environments) |
| State Path | `{env}/terraform.tfstate` | Clear separation per environment |

---

## Setup Instructions

### Prerequisites

```bash
# Ensure you have:
- AWS Account with appropriate permissions
- AWS CLI v2 installed
- Terraform v1.0+
- AWS credentials configured
```

### Step 1: Create S3 Bucket for State Storage

```bash
aws s3api create-bucket \
  --bucket terraform-iac-project-state \
  --region eu-west-2 \
  --create-bucket-configuration LocationConstraint=eu-west-2
```

### Step 2: Enable Versioning on S3 Bucket

Enables rollback to previous state versions:

```bash
aws s3api put-bucket-versioning \
  --bucket terraform-iac-project-state \
  --versioning-configuration Status=Enabled
```

### Step 3: Enable Server-Side Encryption (SSE-S3)

Encrypts state files at rest:

```bash
aws s3api put-bucket-encryption \
  --bucket terraform-iac-project-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### Step 4: Block Public Access to S3 Bucket

Prevents accidental public exposure of state files:

```bash
aws s3api put-public-access-block \
  --bucket terraform-iac-project-state \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### Step 5: Create DynamoDB Table for Locking

```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region eu-west-2
```

### Step 6: Enable DynamoDB Point-in-Time Recovery (Optional but Recommended)

```bash
aws dynamodb update-continuous-backups \
  --table-name terraform-locks \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region eu-west-2
```

### Step 7: Initialize Terraform with Remote Backend

```bash
cd environments/dev

# Remove local state if it exists
rm -f terraform.tfstate terraform.tfstate.backup

# Initialize with remote backend
terraform init

# Select "yes" when prompted to migrate state to remote backend
```

### Step 8: Verify Backend Configuration

```bash
# Check that Terraform is using remote backend
terraform state list

# Inspect S3 bucket for state files
aws s3 ls s3://terraform-iac-project-state/ --recursive

# Verify DynamoDB table
aws dynamodb describe-table --table-name terraform-locks --region eu-west-2
```

---

## State File Management

### Understanding Terraform State

**State File Contents:**

```json
{
  "version": 4,
  "terraform_version": "1.0.0",
  "serial": 42,
  "lineage": "abc123-def456",
  "outputs": { ... },
  "resources": [
    {
      "type": "aws_vpc",
      "name": "main",
      "instances": [ ... ]
    }
  ]
}
```

**Key Fields:**

| Field | Purpose |
|-------|---------|
| `version` | State format version |
| `serial` | Incremental counter (increments per apply) |
| `lineage` | Unique ID for this state file (persists across refreshes) |
| `resources` | All managed infrastructure resources |

### State File Isolation (Per-Environment)

```
dev/terraform.tfstate     → Contains: VPC, EC2, RDS for DEV
staging/terraform.tfstate → Contains: VPC, EC2, RDS for STAGING
prod/terraform.tfstate    → Contains: VPC, EC2, RDS for PROD
```

**Benefits:**
- Environment isolation (changes to dev don't affect prod)
- Independent locking (dev operations don't block prod)
- Separate state versioning
- Clear audit trail per environment

### Viewing Current State

```bash
# List all managed resources
terraform state list

# Show details of a specific resource
terraform state show aws_vpc.main

# Output actual values
terraform output

# Manual state inspection (local copy)
terraform state pull > state-backup.json
```

---

## Security Best Practices

### 1. Restrict S3 Bucket Access via IAM

**Principle:** Only Terraform runners should access the state bucket.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowTerraformStateAccess",
      "Effect": "Allow",
      "Principal": {
        "IAM": "arn:aws:iam::123456789012:role/TerraformRole"
      },
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-iac-project-state",
        "arn:aws:s3:::terraform-iac-project-state/*"
      ]
    }
  ]
}
```

### 2. Enable S3 Bucket Logging

Track all access to state files:

```bash
aws s3api put-bucket-logging \
  --bucket terraform-iac-project-state \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "terraform-iac-project-state-logs",
      "TargetPrefix": "access-logs/"
    }
  }'
```

### 3. Require MFA Delete (Optional)

Prevents accidental deletion without MFA authentication:

```bash
aws s3api put-bucket-versioning \
  --bucket terraform-iac-project-state \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::123456789012:mfa/your-mfa" <mfa-code>
```

### 4. Enable CloudTrail Logging

Audit all API calls to S3 and DynamoDB:

```bash
aws cloudtrail create-trail \
  --name terraform-backend-trail \
  --s3-bucket-name terraform-cloudtrail-logs

aws cloudtrail start-logging \
  --trail-name terraform-backend-trail
```

### 5. Encrypt DynamoDB at Rest

DynamoDB encryption (KMS) for locks table:

```bash
aws dynamodb update-table \
  --table-name terraform-locks \
  --sse-specification Enabled=true,SSEType=KMS,KeyArn=arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012
```

### 6. Never Commit State Files

Add to `.gitignore`:

```
terraform.tfstate
terraform.tfstate.*
.terraform/
.terraform.lock.hcl
*.tfvars
!*.tfvars.example
```

---

## Common Backend Operations

### Initializing Backend (First Time)

```bash
cd environments/dev
terraform init
# Output:
# Initializing the backend...
# Successfully configured the backend "s3"!
```

### Pulling Latest State (Multi-Team Scenario)

```bash
# Refresh local state copy from remote backend
terraform refresh

# Or, re-initialize if needed
terraform init -reconfigure
```

### Locking Behavior During Operations

**Scenario: Two team members running terraform apply simultaneously**

```
User A: terraform apply                User B: terraform apply
├─ Acquires lock on DynamoDB          ├─ Attempts to acquire lock
├─ Lock ID: terraform-iac-project-state-dev
├─ Lock Info:                          ├─ BLOCKED (waiting for lock)
│  {                                   │
│    "ID": "abc123",                  │
│    "Operation": "OperationTypeApply",│
│    "Info": "User A's machine",      │
│    "Who": "User A",                 │
│    "Version": "1.0.0",              │
│    "Created": "2026-06-15T10:30Z"  │
│  }                                  │
├─ Executes changes                    │
├─ Uploads updated state               │
└─ Releases lock                       └─ Lock acquired, proceeds
```

### Removing Stuck Locks

If a lock is stuck (Terraform crash without cleanup):

```bash
# List locks
aws dynamodb scan --table-name terraform-locks --region eu-west-2

# Force delete lock (use with caution!)
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"terraform-iac-project-state-dev"}}' \
  --region eu-west-2
```

---

## Disaster Recovery

### Scenario 1: State File Corruption

**Recovery via S3 Versioning:**

```bash
# List all versions of state file
aws s3api list-object-versions \
  --bucket terraform-iac-project-state \
  --prefix dev/terraform.tfstate

# Restore previous version
aws s3api get-object \
  --bucket terraform-iac-project-state \
  --key dev/terraform.tfstate \
  --version-id abc123def456 \
  state-backup.json

# Copy restored state back
aws s3 cp state-backup.json \
  s3://terraform-iac-project-state/dev/terraform.tfstate
```

### Scenario 2: Entire S3 Bucket Deleted

**Recovery via Backup:**

```bash
# If enabled, recover from AWS Backup or S3 Cross-Region Replication:
aws s3 cp s3://terraform-state-backup/dev/terraform.tfstate \
  s3://terraform-iac-project-state/dev/terraform.tfstate
```

### Scenario 3: DynamoDB Lock Table Corruption

**Recovery:**

```bash
# Create new locks table
aws dynamodb create-table \
  --table-name terraform-locks-new \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

# Update backend.tf to use new table temporarily
# Apply: terraform init -reconfigure

# Delete old table
aws dynamodb delete-table --table-name terraform-locks
```

---

## Troubleshooting

### Issue 1: "Error acquiring the state lock"

**Cause:** Another Terraform operation is running or lock is stuck.

**Solution:**

```bash
# Check active locks
aws dynamodb scan --table-name terraform-locks

# If stuck, delete the lock
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"terraform-iac-project-state-dev"}}'

# Retry terraform apply
terraform apply
```

### Issue 2: "NoSuchBucket" error on terraform init

**Cause:** S3 bucket doesn't exist or wrong bucket name.

**Solution:**

```bash
# Verify bucket exists
aws s3 ls terraform-iac-project-state

# Create bucket if missing
aws s3api create-bucket \
  --bucket terraform-iac-project-state \
  --region eu-west-2 \
  --create-bucket-configuration LocationConstraint=eu-west-2
```

### Issue 3: "InvalidParameterException" on DynamoDB

**Cause:** DynamoDB table doesn't exist.

**Solution:**

```bash
# Create DynamoDB table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### Issue 4: "AccessDenied" errors

**Cause:** IAM permissions insufficient.

**Solution:**

```bash
# Verify IAM user/role has permissions:
aws iam get-user
aws sts get-caller-identity

# Attach required policy (see Security Best Practices section)
aws iam put-user-policy \
  --user-name your-user \
  --policy-name terraform-backend-policy \
  --policy-document file://policy.json
```

### Issue 5: State file locked from CI/CD pipeline

**Cause:** Pipeline crashed without releasing lock.

**Solution:**

```bash
# In CI/CD pipeline, set lock timeout:
terraform apply -lock=true -lock-timeout=5m

# Or use try/catch to ensure cleanup
# (implementation depends on CI/CD platform)
```

---

## Monitoring & Maintenance

### CloudWatch Metrics for S3

```bash
# Monitor S3 operations
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name NumberOfObjects \
  --dimensions Name=BucketName,Value=terraform-iac-project-state Name=StorageType,Value=AllStorageTypes \
  --start-time 2026-06-15T00:00:00Z \
  --end-time 2026-06-15T23:59:59Z \
  --period 86400 \
  --statistics Average
```

### DynamoDB Monitoring

```bash
# Monitor DynamoDB throughput
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=terraform-locks \
  --start-time 2026-06-15T00:00:00Z \
  --end-time 2026-06-15T23:59:59Z \
  --period 300 \
  --statistics Sum
```

### Regular Backup Schedule

```bash
# Daily backup of state files
aws s3 sync \
  s3://terraform-iac-project-state \
  /local/backups/terraform-state \
  --delete

# Archive monthly
tar -czf terraform-state-2026-06.tar.gz /local/backups/terraform-state
```

---

## Migration from Local to Remote Backend

If starting with local state files:

```bash
cd environments/dev

# 1. Backup local state
cp terraform.tfstate terraform.tfstate.backup

# 2. Initialize remote backend (will prompt about migration)
terraform init

# Choose: yes - to copy existing state to the new remote backend

# 3. Verify remote state was created
aws s3 ls s3://terraform-iac-project-state/dev/

# 4. Delete local state (after verification)
rm -f terraform.tfstate terraform.tfstate.backup
```

---

## Architecture Diagram: Complete Backend Flow

```
┌─────────────────────────────────────────────────────────┐
│                   Developer Workstation                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  $ terraform apply                               │  │
│  │  1. Read backend.tf config                       │  │
│  │  2. Authenticate with AWS credentials            │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────┬──────────────────────────────────┘
                      │ AWS API Calls (HTTPS)
         ┌────────────┴────────────┐
         │                         │
         ▼                         ▼
  ┌────────────────┐      ┌─────────────────┐
  │  AWS STS       │      │   IAM            │
  │  (Auth Token)  │      │   (Validation)   │
  └────────────────┘      └─────────────────┘
         │                         │
         └────────────┬────────────┘
                      │ Signed Request
         ┌────────────┴────────────┐
         │                         │
         ▼                         ▼
  ┌──────────────────┐    ┌──────────────────┐
  │  S3 Bucket       │    │  DynamoDB        │
  │  (State)         │    │  (Locks)         │
  │                  │    │                  │
  │  PUT/GET/DELETE  │    │  PutItem/        │
  │  terraform.      │    │  DeleteItem      │
  │  tfstate         │    │                  │
  │                  │    │  LockID:         │
  │ Versioning ✓     │    │  dev/state       │
  │ Encryption ✓     │    │                  │
  │ Access Logs ✓    │    │  TTL: 30s        │
  └──────────────────┘    └──────────────────┘
         │                         │
         ▼                         ▼
  ┌──────────────────┐    ┌──────────────────┐
  │  CloudTrail      │    │  CloudWatch      │
  │  (Audit Log)     │    │  (Metrics)       │
  └──────────────────┘    └──────────────────┘
```

---

## Reference: Backend Configuration Options

```hcl
terraform {
  backend "s3" {
    # Required
    bucket = "terraform-iac-project-state"    # S3 bucket name
    key    = "dev/terraform.tfstate"           # State file path
    region = "eu-west-2"                       # AWS region

    # Optional but recommended
    dynamodb_table = "terraform-locks"         # DynamoDB table for locking
    encrypt        = true                      # SSE-S3 encryption
    
    # Advanced options
    # acl            = "private"                # ACL (default: private)
    # skip_credentials_validation = false       # Skip AWS credential check
    # skip_region_validation = false            # Skip region validation
    # skip_metadata_api_check = false           # Skip EC2 metadata check
    # sse_kms_key_id = "arn:aws:kms:..."        # Use KMS instead of AES256
    # workspace_key_prefix = "env"              # Terraform workspaces
  }
}
```

---

## Summary Checklist

- S3 bucket created with versioning enabled
- S3 bucket encryption enabled (SSE-S3 or KMS)
- S3 bucket public access blocked
- DynamoDB table created for locking
- IAM policies restrict access to authorized users/roles
- Backend configuration added to each environment's `backend.tf`
- `terraform init` run successfully
- Remote state verified with `terraform state list`
- CloudTrail enabled for audit logging
- Backup strategy in place

---

**Last Updated:** June 15, 2026  
**Region:** eu-west-2 (London)  
**State Backend:** AWS S3 + DynamoDB  
**Encryption:** AES-256 (SSE-S3)
