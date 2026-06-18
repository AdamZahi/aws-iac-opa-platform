# CloudFormation Templates

> **Note:** These templates exist for **learning and comparison purposes only**.
> In production, we use Terraform exclusively. These templates mirror the same
> infrastructure that the Terraform modules provision, so you can compare the
> two approaches side by side.

---

## What's Here

| File | Terraform Equivalent | What it Creates |
|------|----------------------|-----------------|
| `backend.yaml` | `backend/s3.tf` + `backend/dynamodb.tf` | S3 bucket for Terraform state + DynamoDB lock table |
| `vpc.yaml` | `modules/vpc/` | VPC, public/private subnets, Internet Gateway, route tables |
| `ec2.yaml` | `modules/ec2/` | Security Group + EC2 web server instance |
| `rds.yaml` | `modules/rds/` | DB Subnet Group, Security Group + MySQL RDS instance |

---

## Architecture

```
Internet
    │
    ▼
Internet Gateway
    │
    ├── Public Subnet 1 (AZ-1) ──► EC2 Instance (web server)
    └── Public Subnet 2 (AZ-2)

    ├── Private Subnet 1 (AZ-1) ──► RDS Instance (MySQL)
    └── Private Subnet 2 (AZ-2)     (only EC2 can connect to it)
```

---

## Deployment Order

> **CloudFormation stacks depend on each other via cross-stack references.**
> You MUST deploy them in this order:

### Step 1 — Backend (optional, only needed for Terraform)
```bash
aws cloudformation deploy \
  --template-file backend.yaml \
  --stack-name terraform-iac-backend \
  --region eu-west-2
```

### Step 2 — VPC (must be first)
```bash
aws cloudformation deploy \
  --template-file vpc.yaml \
  --stack-name terraform-iac-project-dev-vpc \
  --region eu-west-2
```

### Step 3 — EC2 (needs VPC outputs)
```bash
aws cloudformation deploy \
  --template-file ec2.yaml \
  --stack-name terraform-iac-project-dev-ec2 \
  --parameter-overrides KeyName=your-key-pair-name \
  --region eu-west-2
```

### Step 4 — RDS (needs VPC + EC2 outputs)
```bash
aws cloudformation deploy \
  --template-file rds.yaml \
  --stack-name terraform-iac-project-dev-rds \
  --parameter-overrides DBPassword=YourSecurePassword123 \
  --region eu-west-2
```

---

## How Cross-Stack References Work

Terraform modules share values via `outputs.tf` + `variables.tf`.
CloudFormation does the same with **Exports** and **ImportValue**.

**In vpc.yaml (exporting):**
```yaml
Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: terraform-iac-project-dev-VpcId   # Published name
```

**In ec2.yaml (importing):**
```yaml
VpcId:
  Fn::ImportValue: terraform-iac-project-dev-VpcId   # Reads the exported value
```

This is exactly like Terraform's `module.vpc.vpc_id` output reference.

---

## Terraform vs CloudFormation Comparison

| Concept | Terraform | CloudFormation |
|---------|-----------|----------------|
| Template file | `.tf` files | `.yaml` / `.json` files |
| Resource block | `resource "aws_vpc" "main" {}` | `Type: AWS::EC2::VPC` |
| Variables | `variable "name" {}` | `Parameters:` section |
| Outputs | `output "vpc_id" {}` | `Outputs:` + `Export:` |
| Cross-module refs | `module.vpc.vpc_id` | `Fn::ImportValue` |
| Deploy command | `terraform apply` | `aws cloudformation deploy` |
| State file | `terraform.tfstate` (in S3) | Managed by AWS automatically |
| Destroy | `terraform destroy` | `aws cloudformation delete-stack` |

---

## Cleanup

Delete stacks in **reverse order** (RDS → EC2 → VPC → Backend):

```bash
aws cloudformation delete-stack --stack-name terraform-iac-project-dev-rds   --region eu-west-2
aws cloudformation delete-stack --stack-name terraform-iac-project-dev-ec2   --region eu-west-2
aws cloudformation delete-stack --stack-name terraform-iac-project-dev-vpc   --region eu-west-2
# Backend uses DeletionPolicy: Retain, so deleting the stack won't delete the S3/DynamoDB resources
aws cloudformation delete-stack --stack-name terraform-iac-backend            --region eu-west-2
```