# OPA / Rego Security Policies — Terraform Plan Validation

## Overview

This folder contains **3 Rego security rules** used with [OPA](https://www.openpolicyagent.org/) and [Conftest](https://www.conftest.dev/) to validate Terraform plans **before** any infrastructure is deployed.

---

## Rules Summary

| # | File | Rule | What it blocks |
|---|------|------|----------------|
| 1 | `s3_no_public_access.rego` | No Public S3 Buckets | ACLs: `public-read`, `public-read-write`, `authenticated-read` |
| 2 | `sg_no_open_ssh.rego` | No SSH Open to Internet | Port 22 reachable from `0.0.0.0/0` or `::/0` |
| 3 | `iam_no_wildcard.rego` | No IAM Wildcard Actions | IAM policies with `Action: "*"` |

---

## Usage

### 1. Generate the Terraform plan as JSON
```bash
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > terraform.plan.json
```

### 2. Run Conftest against all policies
```bash
conftest test terraform.plan.json --policy policy/
```

### 3. Run OPA unit tests
```bash
opa test policy/ test/ -v
```

---

## Example Output (on violation)

```
FAIL - terraform.plan.json - terraform.security - ❌ [S3 PUBLIC ACL] Bucket 'my_bucket' uses forbidden ACL 'public-read'. S3 buckets must be private.
FAIL - terraform.plan.json - terraform.security - ❌ [SSH EXPOSED] Security Group 'web_sg' allows SSH (port 22) from the internet (0.0.0.0/0). Restrict to a known CIDR.
FAIL - terraform.plan.json - terraform.security - ❌ [IAM WILDCARD] IAM Policy 'admin_policy' grants Action: '*'. All IAM policies must follow least privilege.
```
