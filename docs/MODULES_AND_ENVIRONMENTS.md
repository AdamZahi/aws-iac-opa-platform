# Terraform Modules and Environments Documentation

## Overview

This project implements Infrastructure as Code (IaC) for AWS using Terraform with a modular architecture. It supports three environments (dev, staging, prod) with reusable modules for VPC, EC2, and RDS infrastructure.

---

## Modules

Modules are reusable components that encapsulate AWS resource configurations. Each module is self-contained with its own variables, resources, and outputs.

### 1. VPC Module (`modules/vpc/`)

**Purpose:** Creates a Virtual Private Cloud (VPC) with public and private subnets across multiple availability zones.

#### Resources Created:
- **VPC**: Main network with configurable CIDR block
- **Internet Gateway**: Enables communication between VPC and the internet
- **Public Subnets**: Multiple subnets with auto-assigned public IPs for load balancers/bastion hosts
- **Private Subnets**: Multiple subnets for internal resources (EC2, RDS)
- **NAT Gateway**: Allows outbound internet access for resources in private subnets
- **Route Tables**: Manages traffic routing for public and private subnets

#### Key Variables:
| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Name used for resource tagging | Required |
| `environment` | Deployment environment (dev/staging/prod) | Required |
| `vpc_cidr` | VPC CIDR block | 10.0.0.0/16 |
| `public_subnet_cidrs` | List of public subnet CIDR blocks | ["10.0.1.0/24", "10.0.2.0/24"] |
| `private_subnet_cidrs` | List of private subnet CIDR blocks | ["10.0.11.0/24", "10.0.12.0/24"] |
| `availability_zones` | List of AZs for subnet distribution | Required |
| `enable_nat_gateway` | Whether to create a NAT Gateway | - |

#### Outputs:
- `vpc_id`: ID of the created VPC
- `public_subnet_ids`: List of public subnet IDs
- `private_subnet_ids`: List of private subnet IDs
- `nat_gateway_id`: ID of the NAT Gateway (if enabled)

#### Network Architecture:
```
┌─────────────────────────────────┐
│         VPC (10.0.0.0/16)        │
├─────────────────────────────────┤
│ Public Subnets (NAT, IGW)        │
│  - 10.0.1.0/24 (AZ-a)            │
│  - 10.0.2.0/24 (AZ-b)            │
├─────────────────────────────────┤
│ Private Subnets (EC2, RDS)       │
│  - 10.0.11.0/24 (AZ-a)           │
│  - 10.0.12.0/24 (AZ-b)           │
└─────────────────────────────────┘
```

---

### 2. EC2 Module (`modules/ec2/`)

**Purpose:** Provisions EC2 instances with security groups and encryption for compute workloads.

#### Resources Created:
- **Security Group**: Controls inbound/outbound traffic
  - SSH access (conditional - only if CIDR blocks provided)
  - Unrestricted egress
- **EC2 Instance**: Main compute resource
  - Runs in private subnet (no public IP by default)
  - Root volume encrypted with gp3 storage (20 GB)
  - Optional IAM instance profile for AWS service access

#### Key Variables:
| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Name for resource tagging | Required |
| `environment` | Deployment environment | Required |
| `vpc_id` | VPC ID for security group | Required |
| `subnet_id` | Private subnet ID for instance | Required |
| `ami_id` | AMI ID (Amazon Linux 2023) | ami-0b45ae66668865cd6 |
| `instance_type` | EC2 instance size | t3.micro |
| `allowed_ssh_cidrs` | CIDR blocks allowed SSH access | [] (empty = SSH disabled) |
| `iam_instance_profile` | IAM instance profile name | null |
| `user_data` | Initialization script | null |

#### Outputs:
- `instance_id`: EC2 instance ID
- `private_ip`: Private IP address
- `security_group_id`: Security group ID

#### Security Design:
- Instances deployed in **private subnets** (no direct internet access)
- SSH is **disabled by default** (recommended for production)
- All data encrypted at rest (root volume)
- Outbound traffic allowed for package updates via NAT Gateway

---

### 3. RDS Module (`modules/rds/`)

**Purpose:** Creates a managed MySQL database with security and high availability features.

#### Resources Created:
- **DB Subnet Group**: Spans private subnets across multiple AZs
- **RDS Security Group**: Restricts access to EC2 instances only
- **RDS Instance**: MySQL database with:
  - Encryption at rest
  - Automated backups
  - Optional Multi-AZ for high availability
  - Storage: 20 GB gp3 by default

#### Key Variables:
| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Resource naming | Required |
| `environment` | Environment name | Required |
| `vpc_id` | VPC ID | Required |
| `subnet_ids` | Private subnet IDs (min 2 AZs) | Required |
| `allowed_security_group_ids` | EC2 security group IDs | Required |
| `db_name` | Initial database name | iacdb |
| `db_username` | Master username | Required (sensitive) |
| `db_password` | Master password | Required (sensitive) |
| `instance_class` | DB instance size | db.t3.micro |
| `allocated_storage` | Storage in GB | 20 |
| `engine_version` | MySQL version | 8.0 |
| `multi_az` | Enable Multi-AZ redundancy | false |
| `skip_final_snapshot` | Skip snapshot on deletion | true |

#### Outputs:
- `db_endpoint`: RDS connection endpoint (host:port)
- `db_name`: Database name
- `rds_security_group_id`: RDS security group ID

#### Network Access:
```
EC2 Instance (Private Subnet)
    ↓ (MySQL port 3306)
RDS Security Group (allows only EC2 sg)
    ↓
RDS Instance (Private Subnet, encrypted)
```

---

### 4. IAM Module (`modules/iam/`)

**Status:** Empty (ready for future expansion)

This module is intended for IAM roles, policies, and instance profiles needed across the infrastructure.

---

## Environments

Each environment represents a complete, isolated deployment of the infrastructure. Environments are differentiated by resource sizes and network CIDR blocks to prevent conflicts.

### Environment Configuration Comparison

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **EC2 Instance** | t3.micro | t3.small | t3.medium |
| **DB Instance** | db.t3.micro | db.t3.small | db.t3.medium |
| **Multi-AZ DB** | No | No (recommended: Yes) | Yes (in future) |
| **Use Case** | Testing, Development | Pre-production testing | Live production |
| **Cost** | Minimal | Low-Medium | Medium-High |

### Public Subnet Configuration
All environments use 2 public subnets (AZ-a and AZ-b):
- Dev: 10.0.1.0/24, 10.0.2.0/24
- Staging: 10.1.1.0/24, 10.1.2.0/24
- Prod: 10.2.1.0/24, 10.2.2.0/24

### Private Subnet Configuration
All environments use 2 private subnets (AZ-a and AZ-b):
- Dev: 10.0.11.0/24, 10.0.12.0/24
- Staging: 10.1.11.0/24, 10.1.12.0/24
- Prod: 10.2.11.0/24, 10.2.12.0/24

---

### Development Environment (`environments/dev/`)

**Purpose:** Quick iteration and testing without production-scale resources.

#### Key Characteristics:
- **Smallest instance types** (t3.micro/micro) for cost optimization
- **Single-AZ database** (no Multi-AZ)
- **Quick snapshots disabled** (faster teardown)
- Placeholder credentials (never commit real values)

#### Configuration Files:
- `main.tf`: Module instantiation (VPC, EC2, RDS)
- `variables.tf`: Environment variable definitions
- `terraform.tfvars`: Dev-specific values (CIDR: 10.0.0.0/16)
- `providers.tf`: AWS provider configuration
- `backend.tf`: Terraform state backend (S3)

#### Common Deployments:
```bash
cd environments/dev
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

---

### Staging Environment (`environments/staging/`)

**Purpose:** Pre-production testing with realistic resource sizes and configurations.

#### Key Characteristics:
- **Medium instance types** (t3.small) for representative testing
- **Simulates production architecture** (but not scale)
- **Baseline for performance testing**
- Uses same database version as production

#### Configuration Files:
Same structure as dev, but with:
- `terraform.tfvars`: Staging-specific values
  - CIDR: 10.1.0.0/16 (no overlap with dev/prod)
  - Instance: t3.small
  - DB: db.t3.small

#### Common Use Cases:
- Testing application features before production
- Load testing within resource limits
- Integration testing with production-like infrastructure
- Training and documentation

---

### Production Environment (`environments/prod/`)

**Purpose:** Live infrastructure supporting end-users with high availability and security.

#### Key Characteristics:
- **Largest instance types** (t3.medium) for performance
- **Encrypted storage** and **secure networking**
- **Multi-AZ database** (planned for high availability)
- **Final snapshots enabled** (data retention on deletion)
- Isolated network (10.2.0.0/16)

#### Configuration Files:
Same structure, with `terraform.tfvars` containing:
- CIDR: 10.2.0.0/16
- Instance: t3.medium
- DB: db.t3.medium
- `skip_final_snapshot`: false (data protection)

#### Security Best Practices:
- Credentials managed via **AWS Secrets Manager** (not in tfvars)
- State file stored in **encrypted S3 backend**
- State locking via **DynamoDB**
- All resources encrypted at rest
- SSH access disabled by default

---

## Module Usage in Environments

Each environment's `main.tf` instantiates all modules with environment-specific values:

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # Pass environment-specific variables
  vpc_cidr = var.vpc_cidr  # Dev: 10.0.0.0/16, Prod: 10.2.0.0/16
}

module "ec2" {
  source = "../../modules/ec2"
  subnet_id = module.vpc.private_subnet_ids[0]  # Use VPC outputs
}

module "rds" {
  source = "../../modules/rds"
  allowed_security_group_ids = [module.ec2.security_group_id]  # Cross-module reference
}
```

This pattern enables:
- **Code reuse** across environments
- **Consistent infrastructure design**
- **Environment-specific scaling** (via variables only)
- **Modular testing** (test modules independently)

---

## Infrastructure Architecture Summary

```
                    ┌─────────────────────────┐
                    │   AWS Account Region    │
                    │   (eu-west-2)           │
                    └─────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
              ┌─────▼────┐        ┌─────▼────┐
              │   Dev    │        │   Prod   │
              │ VPC      │        │ VPC      │
              │10.0/16   │        │10.2/16   │
              └─────┬────┘        └─────┬────┘
                    │                   │
        ┌───────────┼───────────┐   ┌───────────┼───────────┐
        │           │           │   │           │           │
    ┌───▼──┐    ┌───▼──┐   ┌───▼──┐ ┌───▼──┐ ┌───▼──┐  ┌───▼──┐
    │Public│    │Public│   │Priv  │ │Public│ │Public│  │Priv  │
    │  SN  │    │  SN  │   │ SN   │ │  SN  │ │  SN  │  │ SN   │
    └──────┘    └──────┘   └──┬───┘ └──────┘ └──────┘  └──┬───┘
                              │                          │
                          ┌───▼───┐                  ┌───▼───┐
                          │ EC2   │                  │ EC2   │
                          │(micro)│                  │(med)  │
                          └───┬───┘                  └───┬───┘
                              │                         │
                          ┌───▼────────┐            ┌───▼────────┐
                          │   RDS      │            │   RDS      │
                          │ (t3.micro) │            │(t3.medium) │
                          └────────────┘            └────────────┘
```

---

## Deployment Workflow

### Prerequisites:
```bash
# Install Terraform
terraform version  # Ensure v1.0+

# Configure AWS credentials
aws configure
export AWS_PROFILE=<your_profile>
```

### Deploying an Environment:
```bash
cd environments/dev  # or staging/prod

# Review planned changes
terraform plan -var-file=terraform.tfvars

# Apply infrastructure
terraform apply -var-file=terraform.tfvars

# View outputs
terraform output
```

### Destroying an Environment:
```bash
cd environments/dev

# Review what will be deleted
terraform plan -destroy -var-file=terraform.tfvars

# Confirm deletion
terraform destroy -var-file=terraform.tfvars
```

---

## Best Practices Implemented

### Security:
- **Encrypted storage** (RDS and EC2 root volumes)
- **Network isolation** (private subnets for compute/database)
- **Security groups** (least-privilege access)
- **SSH disabled by default** (explicit CIDR blocks required)
- **Sensitive variables** marked (`db_password`, `db_username`)

### Maintainability:
- **Modular design** (reusable across environments)
- **Consistent tagging** (project, environment, managed-by)
- **Clear outputs** (for cross-module reference)
- **Variable documentation** (descriptions and types)
- **Isolated state** (per-environment state files)

### Cost Optimization:
- **Environment-specific sizing** (dev uses t3.micro, prod uses t3.medium)
- **Optional NAT Gateway** (for outbound-only workloads)
- **Snapshot management** (skip in dev, keep in prod)
- **Minimal default storage** (20 GB, adjustable)

### Scalability:
- **Multi-AZ support** (across 2 availability zones)
- **Modular subnet design** (easy to add more)
- **Multi-AZ RDS** (optional, recommended for prod)
- **NAT Gateway for scale** (outbound traffic management)

---

## Future Enhancements

1. **IAM Module**: Expand with roles, policies, and instance profiles
2. **Monitoring**: Add CloudWatch dashboards and alarms
3. **Auto-Scaling**: Implement ASGs for dynamic scaling
4. **Load Balancing**: Add Application Load Balancer (ALB)
5. **CI/CD Integration**: GitHub Actions for automated deployments
6. **Backup Strategy**: Enhanced snapshot and recovery procedures
7. **Multi-Region**: Extend infrastructure across multiple AWS regions

---

## Support & Troubleshooting

### Common Issues:

**Issue: State file conflicts**
- Solution: Ensure DynamoDB lock is enabled in backend.tf

**Issue: VPC CIDR overlap**
- Solution: Verify each environment has unique CIDR (dev: 10.0, staging: 10.1, prod: 10.2)

**Issue: Database connection failures**
- Solution: Check security group allows EC2 security group ID

**Issue: EC2 cannot reach internet**
- Solution: Verify NAT Gateway is created and route table includes route to NAT

---

**Last Updated:** June 15, 2026  
**Project:** Smartovate Infrastructure  
**Region:** eu-west-2 (London)
