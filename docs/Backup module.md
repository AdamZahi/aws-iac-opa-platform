# US 5.1 — Automated Backups

**Epic:** Disaster Recovery
**Status:** Implemented
**Type:** Reusable Terraform Module

## Objective

As a Cloud Engineer, configure automated backups of critical resources
(RDS, EC2/EBS) with a retention policy to ensure data recovery in case of
incident or accidental deletion.

## Directory Structure

```
modules/backup/
├── main.tf              # Vault, plan, selection, IAM role, alarm
├── variables.tf         # Module input variables
├── outputs.tf           # Vault/plan ARNs, native RDS parameters
├── example-usage.tf     # Example usage + resource attachment
└── scripts/
    └── restore-test.sh  # Validation script via restore test
```

## Chosen Approach

The module relies on **AWS Backup**, AWS's unified managed backup service,
rather than separate mechanisms (Data Lifecycle Manager for EBS + manual RDS
snapshots). This choice was made for:

- **A single retention policy**, applied consistently to RDS and EC2/EBS,
  instead of two separate systems to maintain.
- **Tag-based selection** (`Backup=true`): any newly tagged resource is
  automatically covered without modifying the module's Terraform code.
- **Centralized notifications and vault**, with optional **Vault Lock** to
  protect against malicious or accidental deletion of backups themselves.

Additionally, **native RDS automatic backups** (`backup_retention_period`)
remain enabled to benefit from **point-in-time recovery**, which AWS Backup
alone does not provide with the same granularity.

## Implemented Components

### 1. Backup Vault (`aws_backup_vault.this`)

Centralized, encrypted storage for all recovery points (RDS and EC2/EBS
snapshots combined).

### 2. Backup Plan (`aws_backup_plan.this`)

Two combined rules:

| Rule | Frequency | Default Retention | Objective |
|---|---|---|---|
| `daily-backups` | Daily (03:00 UTC) | 7 days | Fast recovery from recent incident |
| `weekly-backups` | Weekly (Sunday 04:00 UTC) | 28 days | Cover late-detected incidents |

All values (schedules, retentions, start/completion windows) are
configurable via `variables.tf`. Transition to cold storage is possible via
`cold_storage_after_days` (AWS constraint: ≥ 90 days if enabled).

### 3. Backup Selection (`aws_backup_selection.this`)

**Tag-based selection**: any RDS or EC2/EBS resource with the `Backup=true`
tag is automatically included in the plan. An explicit list of ARNs
(`additional_resource_arns`) allows covering untagged edge cases.

### 4. IAM Role (`aws_iam_role.backup`)

Dedicated role for `backup.amazonaws.com` service, with AWS managed policies
`AWSBackupServiceRolePolicyForBackup` and
`AWSBackupServiceRolePolicyForRestores` — no application permissions,
consistent with the least-privilege approach used throughout the project.

### 5. Notifications and Alarm

- `aws_backup_vault_notifications`: notifies via SNS on backup failures,
  expiration, or restore events (native AWS Backup events).
- `aws_cloudwatch_metric_alarm.backup_job_failed`: CloudWatch alarm on
  `NumberOfBackupJobsFailed`, consistent with the alerting pattern already
  used in US 4.1 and 6.1.

### 6. Vault Lock (optional, disabled by default)

`enable_vault_lock = true` enables a lock preventing backup deletion before
expiration, even by an admin account, once in `compliance` mode. **Warning:
this mode is irreversible** — only enable after validating the retention
policy in production-like environments.

## Key Variables

```hcl
project_name = "iac-aws-project"
environment   = "dev"

backup_selection_tag_key   = "Backup"
backup_selection_tag_value = "true"

daily_backup_schedule = "cron(0 3 * * ? *)"
daily_retention_days  = 7

weekly_backup_schedule = "cron(0 4 ? * SUN *)"
weekly_retention_days  = 28

rds_backup_retention_period = 7
rds_backup_window           = "02:00-03:00"

sns_topic_arn    = "arn:aws:sns:eu-west-1:xxxx:alerts"
enable_vault_lock = false
```

See `variables.tf` for the complete list.

## Usage

```hcl
module "backup" {
  source = "../../modules/backup"

  project_name  = "iac-aws-project"
  environment   = "dev"
  sns_topic_arn = module.alerting.sns_topic_arn
}
```

To enable backups for a resource, simply add the `Backup = "true"` tag:

```hcl
resource "aws_db_instance" "app" {
  # ...
  backup_retention_period = module.backup.rds_native_backup_settings.backup_retention_period
  backup_window           = module.backup.rds_native_backup_settings.backup_window

  tags = {
    Backup = "true"
  }
}
```

For EC2 instances managed by the `asg` module (US 6.1), add
`Backup = "true"` in the Launch Template's `tag_specifications` — see the
comment in `example-usage.tf`.

## Restore Testing (validating backup reliability)

A backup that has never been restored is not a reliable backup. The
`scripts/restore-test.sh` script covers three steps:

```bash
# 1. List available recovery points
./restore-test.sh list <vault-name>

# 2. Start a test restore (to a temporary resource)
./restore-test.sh restore <vault-name> <recovery-point-arn> RDS
./restore-test.sh restore <vault-name> <recovery-point-arn> EC2

# 3. Track job progress
./restore-test.sh status <restore-job-id>
```

**Recommended acceptance procedure (execute at least once, then periodically,
e.g., quarterly):**

1. Wait for at least one successful daily backup job to complete (verifiable
   via `aws backup list-backup-jobs`).
2. Restore this recovery point to a temporary resource (test RDS instance or
   EBS volume, never to production).
3. Functionally validate the restored resource: database connection and data
   integrity check for RDS, volume mount and content verification for
   EC2/EBS.
4. **Delete the test resource** to avoid unnecessary costs.
5. Document the result (success/failure, restore duration) in the team's
   Disaster Recovery runbook.

## Verification / Acceptance

- [ ] The `terraform apply` plan creates the vault, plan, and selection
      without error.
- [ ] An RDS resource tagged `Backup=true` appears in `aws backup
      list-backup-jobs` after the next scheduled slot.
- [ ] An EC2 instance from the ASG tagged `Backup=true` also appears.
- [ ] Old recovery points are automatically deleted after the configured
      retention period (verifiable via `list-recovery-points-by-backup-vault`
      after the delay).
- [ ] An SNS notification is received on simulated failure (e.g., temporarily
      remove an IAM permission then observe the next job failure).
- [ ] A complete restore test has been executed successfully (see procedure
      above).

## Points of Attention / Known Limitations

- **Cost**: AWS Backup charges for storage of recovery points (and restore
  fees). Cold storage reduces costs beyond 90 days but increases restore
  latency — balance with the FinOps team based on data criticality.
- **Vault Lock in compliance mode is irreversible**: never enable directly
  in production without prior validation in dev/staging.
- **Tag-based selection depends on tagging discipline**: a critical resource
  not tagged `Backup=true` will not be backed up. Eventually, an OPA/Conftest
  rule could enforce this tag on all RDS/EC2 resources in production (see
  the project's Compliance-as-Code Epic).
- **RDS "backup_retention_period" and AWS Backup are complementary, not
  redundant**: the former provides point-in-time recovery (second-level
  restoration over 7 days), the latter provides scheduled snapshots with long
  retention and multi-service coverage.

## Suggested Next Steps

- Add an OPA rule enforcing the `Backup=true` tag on all RDS/EC2 resources
  tagged `Environment=prod`.
- Extend selection to other resource types supported by AWS Backup if the
  project adds them (EFS, DynamoDB, etc.).
- Automate the quarterly restore test via a scheduled task (EventBridge +
  Lambda) rather than manual script execution.
