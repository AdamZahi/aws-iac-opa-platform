# CloudFormation Templates — Basic Infrastructure

> **Epic: Templates CloudFormation Management**  
> **Ticket: Create CloudFormation templates for basic infrastructure**  
> US: VPCs, subnets, and security groups — mirroring the Terraform modules for direct comparison.

---

## Repository Structure

```
cloudformation/
├── root-stack.yaml              # Entry point — orchestrates nested stacks
├── deploy.sh                    # Upload to S3 + deploy script
├── network/
│   └── vpc.yaml                 # VPC, subnets, IGW, NAT GW, route tables
└── security/
    └── security-groups.yaml     # Bastion, Web, App, DB, Egress-only SGs
```

---

## Quick Start

```bash
# Configure AWS credentials first
export AWS_PROFILE=my-profile

# Deploy to dev (eu-west-1 by default)
chmod +x deploy.sh
./deploy.sh dev eu-west-1

# Deploy to prod
./deploy.sh prod eu-west-1
```

---

## Architecture Deployed

```
VPC (10.0.0.0/16)
├── Public Subnet AZ1 (10.0.0.0/24)  ──┐
├── Public Subnet AZ2 (10.0.1.0/24)  ──┼── Internet Gateway → Internet
│                                        │    NAT Gateway (AZ1)
├── Private Subnet AZ1 (10.0.10.0/24) ──┘ (routes via NAT)
└── Private Subnet AZ2 (10.0.11.0/24) ── (routes via NAT or NAT2)

Security Groups (layered, source-SG references):
  Internet → [WebSG] → [AppSG] → [DbSG]
  [BastionSG] → [AppSG]   (SSH for debugging only)
  [EgressOnlySG]           (Lambda / monitoring agents)
```

---

## CFN vs Terraform — Direct Comparison

| Concept | CloudFormation | Terraform |
|---|---|---|
| **Variables / inputs** | `Parameters` block | `variable {}` blocks |
| **Conditional resources** | `Conditions` + `!If` | `count` or `for_each` with ternary |
| **Cross-stack references** | `Fn::ImportValue` (export by name) | `terraform_remote_state` or module outputs |
| **Tagging** | `Tags` list on each resource | `default_tags` in provider + per-resource |
| **String interpolation** | `!Sub "${Var}-suffix"` | `"${var.name}-suffix"` |
| **Output reuse in same stack** | `!GetAtt Resource.Attr` / `!Ref` | `resource.type.name.attribute` |
| **Loops** | No native loop (use nested stacks or macros) | `for_each`, `count`, `dynamic` |
| **State management** | Managed by AWS (no S3 bucket needed) | Requires S3 + DynamoDB backend |
| **Plan / dry-run** | Change Sets (`aws cloudformation create-change-set`) | `terraform plan` |
| **Drift detection** | Built-in: `DetectStackDrift` API | `terraform plan` shows drift |
| **Module reuse** | Nested stacks (TemplateURL in S3) | `module {}` blocks |
| **Secret injection** | `{{resolve:ssm-secure:/path}}` | `data "aws_secretsmanager_secret"` |

### Key Behavioural Differences

**State**  
CloudFormation state lives entirely inside AWS — no S3 bucket to provision. Terraform requires the S3 + DynamoDB backend configured in US 1.1.

**Loops and dynamic resources**  
Terraform's `for_each` makes it trivial to create N subnets from a list. In CloudFormation you enumerate each resource (PublicSubnet1, PublicSubnet2, …) or use CloudFormation Macros / transforms, which adds complexity.

**Cross-stack references**  
CFN `Fn::ImportValue` is stricter than Terraform remote state — you cannot delete a stack that exports a value being imported elsewhere. This prevents accidental breakage but makes refactoring harder.

**Drift detection**  
CFN's `DetectStackDrift` is built-in and reports per-resource property-level changes. Terraform drift is revealed on next `plan` and requires running it proactively (hence the drift-detection Lambda in US 3.2).

---

## Parameters Reference

### `network/vpc.yaml`

| Parameter | Default | Description |
|---|---|---|
| `ProjectName` | `iac-comparison` | Prefix for all resource names |
| `Environment` | `dev` | `dev \| staging \| prod` |
| `VpcCidr` | `10.0.0.0/16` | VPC CIDR |
| `PublicSubnet1Cidr` | `10.0.1.0/24` | Public subnet, AZ1 |
| `PublicSubnet2Cidr` | `10.0.2.0/24` | Public subnet, AZ2 |
| `PrivateSubnet1Cidr` | `10.0.10.0/24` | Private subnet, AZ1 |
| `PrivateSubnet2Cidr` | `10.0.11.0/24` | Private subnet, AZ2 |
| `AvailabilityZone1` | `eu-west-1a` | First AZ |
| `AvailabilityZone2` | `eu-west-1b` | Second AZ |
| `EnableNatGateway` | `true` | `false` skips NAT GW (saves cost in dev) |
| `SingleNatGateway` | `true` | `false` deploys one NAT GW per AZ for HA |

### `security/security-groups.yaml`

| Parameter | Default | Description |
|---|---|---|
| `NetworkStackName` | `iac-comparison-dev-network` | Source stack for `Fn::ImportValue` |
| `ProjectName` | `iac-comparison` | Must match VPC stack |
| `Environment` | `dev` | Must match VPC stack |
| `BastionAllowedCidr` | `0.0.0.0/0` | **Restrict in prod** to corporate IP range |
