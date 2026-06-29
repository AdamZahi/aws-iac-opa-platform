# CI/CD Pipeline Documentation

## Overview

This project implements a **three-stage automated CI/CD pipeline** for infrastructure-as-code (IaC) management using Terraform and OPA (Open Policy Agent) for policy validation. The pipeline ensures code quality, compliance, and safe infrastructure deployments.

## Pipeline Architecture

The pipeline consists of three independent GitHub Actions workflows that work together to provide complete infrastructure lifecycle management:

```
┌─────────────────┐
│  Code Change    │
└────────┬────────┘
         │
         ▼
    ┌─────────────────────────────────────────────────┐
    │  1. Validate & OPA (Pull Requests)              │
    │     • Terraform validate                        │
    │     • Terraform plan                            │
    │     • OPA policy checks                         │
    │     • Results posted to PR                      │
    └────────┬────────────────────────────────────────┘
             │ (Approval required)
             ▼
    ┌─────────────────────────────────────────────────┐
    │  2. Deploy (Main branch merge)                  │
    │     • Downloads validated plan                 │
    │     • Terraform apply                          │
    │     • Captures outputs                         │
    │     • Manual approval gate                     │
    └────────┬────────────────────────────────────────┘
             │
             ▼
    ┌─────────────────────────────────────────────────┐
    │  3. Drift Detection (Scheduled + Manual)        │
    │     • Runs every 2 hours                       │
    │     • Compares desired vs actual state         │
    │     • Creates GitHub issue on drift            │
    └─────────────────────────────────────────────────┘
```

---

## Workflow 1: Validate & OPA (`01-validate.yml`)

### Purpose
Runs on every Pull Request targeting `main` branch to validate Terraform code and enforce compliance policies before code review approval.

### Trigger
- **Event**: Pull requests
- **Target branch**: `main`
- **Paths watched**: 
  - `environments/**`
  - `modules/**`
  - `policies/**`

### Key Steps

1. **Checkout & Setup**
   - Clones repository
   - Installs Terraform v1.9.8
   - Configures AWS credentials

2. **Terraform Validation**
   - `terraform fmt` - checks code formatting
   - `terraform validate` - validates configuration syntax
   - `terraform plan` - generates execution plan

3. **OPA Policy Validation**
   - Installs Conftest v0.63.0
   - Runs Rego policies against Terraform plan
   - Validates compliance with security and operational policies

4. **Results**
   - Plan output posted as PR comment
   - Policy violation warnings displayed
   - Prevents merge if policies fail (branch protection rule)

### Configuration
```yaml
Concurrency: validate-${{ github.ref }}
Cancel in-progress: true (prevents duplicate runs)
Working Directory: environments/dev
Terraform Version: 1.9.8
Conftest Version: 0.63.0
```

---

## Workflow 2: Deploy (`02-deploy.yml`)

### Purpose
Automatically deploys infrastructure changes when code is merged to the `main` branch. Includes manual approval gate and artifact handling.

### Trigger
- **Event**: Push to `main`
- **Paths watched**: Same as validate workflow
  - `environments/**`
  - `modules/**`
  - `policies/**`

### Key Steps

1. **Checkout & Setup**
   - Clones repository
   - Installs Terraform v1.9.8
   - Configures AWS credentials

2. **Plan Artifact Download**
   - Downloads the previously validated Terraform plan artifact
   - Uses same plan that passed OPA validation
   - Ensures consistency: "what was approved is what gets deployed"

3. **Terraform Apply**
   - Executes `terraform apply` with validated plan
   - Uses `-auto-approve` flag (safe since plan was pre-approved)
   - Lock timeout: 120 seconds
   - Sets `TF_VAR_environment: dev`

4. **Output Capture & Storage**
   - Executes `terraform output -json`
   - Stores outputs to `tf_outputs.json`
   - Uploads as artifact (retained for 7 days)

### Configuration
```yaml
Concurrency: deploy-main (only one deploy at a time)
Cancel in-progress: false (queue instead of cancel)
Environment: prod (requires GitHub approval gate)
Working Directory: environments/dev
Terraform Version: 1.9.8
Artifact Retention: 7 days
```

### Approval Gate
The `environment: prod` setting enforces GitHub's manual approval workflow:
- Job requires approval from designated teams/users
- Configured in GitHub repository environment settings
- Prevents accidental deployments
- Approval tracked in deployment history

---

## Workflow 3: Drift Detection (`03-drift-detection.yml`)

### Purpose
Continuously monitors infrastructure state for unintended changes (drift) and alerts when actual infrastructure diverges from Terraform state.

### Trigger
- **Schedule**: Every 2 hours (`0 */2 * * *`)
- **Manual**: Workflow dispatch with environment selection

### Workflow Dispatch Options
When triggered manually from Actions tab:
- **Environment**: dev, staging, or prod
- Allows on-demand drift checks for any environment

### Key Steps

1. **Checkout & Setup**
   - Clones repository
   - Installs Terraform v1.9.8
   - Configures AWS credentials

2. **Drift Detection**
   - Runs `terraform plan -out=tfplan`
   - Parses output to detect resource changes
   - Compares desired state vs actual state

3. **Alert on Drift**
   - Creates GitHub Issue if drift detected
   - Issue includes:
     - Changed resource names
     - Nature of changes
     - Severity assessment
   - Includes remediation steps

### Configuration
```yaml
Schedule: Every 2 hours
Working Directory: environments/dev
Terraform Version: 1.9.8
Manual Trigger: Supported with environment choice
Permissions: Read code, Write issues
```

### Example Alert
```
Title: ⚠️ Drift Detected in Dev Environment

Changes detected:
- aws_instance.web_server: disk_size changed
- aws_security_group.main: rules modified

Please investigate and reconcile state with terraform apply.
```

---

## Shared Configuration

### Environment Variables
```yaml
TF_VERSION:     "1.9.8"
CONFTEST_VERSION: "0.63.0"
TF_WORKING_DIR: environments/dev
```

### AWS Credentials
Provided via GitHub Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

### Permissions
- `contents: read` - Access repository code
- `pull-requests: write` - Post PR comments (validate)
- `issues: write` - Create drift detection issues

### Reusable Action
All workflows use `./.github/actions/setup-terraform` for:
- Terraform installation
- AWS credential configuration
- Terraform lock management

---

## How It Works: Complete Flow

### Pull Request Workflow
1. Developer creates PR targeting `main`
2. `01-validate.yml` triggered automatically
3. Terraform plan generated and validated
4. OPA policies enforced
5. Results posted to PR
6. Code reviewed and approved
7. PR merged to `main`

### Deploy Workflow
1. Merge to `main` triggers `02-deploy.yml`
2. Validated plan artifact downloaded
3. Manual approval required (prod environment)
4. Authorized reviewer approves deployment
5. `terraform apply` executes
6. Infrastructure updated
7. Outputs captured and archived

### Drift Detection Workflow
1. Runs on schedule (every 2 hours) or manual trigger
2. Compares desired state (Terraform) vs actual state (AWS)
3. If drift detected:
   - GitHub Issue created
   - Team alerted
   - Investigation required
4. Fix by:
   - Updating Terraform config
   - Running `terraform apply` OR
   - Manual AWS changes reviewed and documented

---

## Best Practices

### For Developers
1. **Create PRs early** - Get feedback before making large changes
2. **Review plan output** - Understand what resources will change
3. **Check policy violations** - Address OPA warnings before merge
4. **Keep changes focused** - One feature per PR for easier review

### For Operators
1. **Review drift alerts** - Investigate and resolve within 24 hours
2. **Monitor approvals** - Batch deployments efficiently
3. **Archive outputs** - Keep deployment history for audits
4. **Test manually** - Verify deployments in staging before prod

### For Security
1. **Use environment approval gates** - Require multiple eyes on prod
2. **Enable branch protection** - Require passing checks before merge
3. **Rotate credentials** - Regular AWS access key rotation
4. **Audit logs** - Review GitHub deployment history regularly

---

## Troubleshooting

### Validation Fails
- Check Terraform formatting: `terraform fmt -check`
- Validate syntax: `terraform validate`
- Review OPA policy violation messages
- Update code or policies, push new commits

### Deploy Hangs
- Check GitHub Actions logs for state lock issues
- Verify AWS credentials are valid
- Ensure terraform state backend is accessible
- Monitor AWS API rate limits

### Drift Detection False Positives
- Some AWS resources auto-modify (managed by AWS)
- Document expected drift in `.terraformignore`
- Review CloudTrail for unauthorized changes
- Update Terraform resource configuration if needed

### Artifacts Not Downloaded
- Check artifact exists from validate workflow
- Verify artifact name matches: `tfplan-${{ github.sha }}`
- Confirm artifact not expired (7-day retention)
- Review workflow logs for upload errors

---

## Maintenance & Updates

### Regular Tasks
- [ ] Review OPA policies quarterly for compliance updates
- [ ] Update Terraform version when minor releases available
- [ ] Rotate AWS access keys every 90 days
- [ ] Archive old deployment artifacts
- [ ] Review and close resolved drift issues

### Monitoring
- GitHub Actions dashboard for workflow status
- CloudWatch for AWS resource metrics
- AWS CloudTrail for infrastructure changes
- GitHub Issues for drift detection alerts

---

## References

- [Terraform Documentation](https://www.terraform.io/docs)
- [OPA/Rego Documentation](https://www.openpolicyagent.org/docs/latest/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/configure-files.html)

---

**Last Updated**: June 2026
**Version**: 1.0
**Status**: Production Ready
