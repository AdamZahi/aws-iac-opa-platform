# Nested Stacks & Cross-Stack References — IaC Comparison Project

> **Epic: Templates CloudFormation Management**  
> **Ticket: Implement nested stacks and cross-stack references**  
> US: Modular CFN stack organization with cross-references — comparable to Terraform module composition.

---

## Repository Structure

```
cloudformation/
├── Makefile                          # Full lifecycle: lint → upload → plan → deploy → drift → destroy
├── root-stack.yaml                   # Orchestrator — the only template deployed directly
├── network/vpc.yaml                  # Layer 1: VPC, subnets, IGW, NAT GWs, route tables
├── iam/roles.yaml                    # Layer 1: EC2 role, CI/CD OIDC role, CFN exec role
├── security/security-groups.yaml     # Layer 2: Bastion, Web, App, DB, Egress-only SGs
├── parameters/ssm-registry.yaml      # Layer 3: SSM Parameter Store cross-ref consolidation
└── compute/app-asg.yaml              # Layer 4: EC2 Launch Template + Auto Scaling Group
```

---

## Deployment Dependency Graph

```
          ┌─────────────────┐   ┌─────────────────┐
          │  NetworkStack   │   │    IAMStack     │  ← Layer 1 (parallel)
          └────────┬────────┘   └────────┬────────┘
                   │                     │
          ┌────────▼────────┐            │
          │  SecurityStack  │            │            ← Layer 2
          └────────┬────────┘            │
                   │                     │
          ┌────────▼─────────────────────▼────────┐
          │            RegistryStack               │  ← Layer 3
          │     (SSM Parameter Store registry)     │
          └────────────────┬───────────────────────┘
                           │
          ┌────────────────▼────────────────────────┐
          │             ComputeStack (optional)      │  ← Layer 4
          └─────────────────────────────────────────┘
```

---

## Three Cross-Stack Reference Patterns

### A — Fn::ImportValue (strict coupling)
```yaml
# Exporter (vpc.yaml)
Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: !Sub "${ProjectName}-${Environment}-VpcId"

# Consumer (security-groups.yaml)
VpcId:
  Fn::ImportValue: !Sub "${ProjectName}-${Environment}-VpcId"
```
✅ Validated at deploy time. ✅ Deletion protection enforced by AWS.
❌ Cannot rebuild exporting stack while consumers exist. ❌ Hard to rename.

### B — SSM Dynamic References (loose coupling)
```yaml
# Producer (roles.yaml) — writes to SSM
SSMParamEC2ProfileArn:
  Type: AWS::SSM::Parameter
  Properties:
    Name: !Sub "/${ProjectName}/${Environment}/iam/ec2-instance-profile-arn"
    Value: !GetAtt EC2InstanceProfile.Arn

# Consumer (app-asg.yaml) — resolves at deploy time, no stack dependency
IamInstanceProfile:
  Arn: !Sub "{{resolve:ssm:/${ProjectName}/${Environment}/iam/ec2-instance-profile-arn}}"
```
✅ Stacks can be torn down/rebuilt independently.
✅ Auditable in AWS Console under Systems Manager > Parameter Store.
❌ No automatic deletion protection.

### C — !GetAtt Bubbling (within root stack only)
```yaml
# root-stack.yaml — wire child outputs directly
RegistryStack:
  Parameters:
    VpcId: !GetAtt NetworkStack.Outputs.VpcId
```
Cleanest pattern — mirrors Terraform's `module.network.vpc_id` syntax directly.

---

## SSM Parameter Namespace

```
/iac-comparison/dev/
  ├── network/   vpc-id, vpc-cidr, public-subnet-{1,2}-id, private-subnet-{1,2}-id
  ├── security/  bastion-sg-id, web-sg-id, app-sg-id, db-sg-id
  └── iam/       ec2-role-arn, ec2-instance-profile-arn, cfn-exec-role-arn
```

---

## Commands

```bash
make lint                            # cfn-lint all templates
make plan  ENV=dev REGION=eu-west-2  # Change Set dry-run
make deploy ENV=dev REGION=eu-west-2 # Full deploy
make drift ENV=dev                   # Detect manual drift
make outputs ENV=dev                 # Print stack outputs
make destroy ENV=dev                 # Teardown (requires confirmation)
```

---

## CFN Nested Stacks vs Terraform Modules

| Aspect | CloudFormation | Terraform |
|--------|---------------|-----------|
| Child definition | `AWS::CloudFormation::Stack` + S3 URL | `module` block + local/git/registry source |
| Passing inputs | `Parameters` map | `variable` assignments |
| Reading outputs | `!GetAtt Child.Outputs.Key` or `Fn::ImportValue` | `module.name.output` — direct |
| Dependency graph | Manual `DependsOn` | Automatic DAG |
| Loops over modules | Not supported natively | `for_each` on module blocks |
| Template storage | S3 required | Local disk or registry |
| Dry-run | Change Sets | `terraform plan` |
| Drift detection | Built-in `DetectStackDrift` | `terraform plan` shows drift |
| Deletion safety | `Fn::ImportValue` blocks teardown | `terraform destroy` follows dependency order |