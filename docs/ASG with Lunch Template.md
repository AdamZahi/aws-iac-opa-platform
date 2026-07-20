# US 6 — Auto Scaling Group with Launch Template

**Epic:** High Availability and Scalability
**Status:** Implemented
**Type:** Reusable Terraform Module

## Objective

As a Cloud Engineer, set up an Auto Scaling Group based on a Launch Template to ensure high availability and automatic elasticity of compute instances based on load.

## Directory Structure

```
modules/asg/
├── main.tf              # Launch Template, ASG, scaling policies, CloudWatch alarms
├── variables.tf          # Module input variables
├── outputs.tf            # Values exposed by the module
├── example-usage.tf      # Example usage from an environment (dev/staging/prod)
└── scripts/
    └── stress-test.sh    # Script for load testing validation
```

## Implemented Components

### 1. Launch Template (`aws_launch_template.this`)

Replaces deprecated Launch Configurations. Includes:

| Element | Details |
|---|---|
| AMI | `var.ami_id` (provided by caller, e.g., Amazon Linux 2023 AMI data source) |
| Instance type | `var.instance_type` (default: `t3.micro`) |
| IAM profile | `var.iam_instance_profile_name` (existing least-privilege role) |
| User-data | `var.user_data`, automatically base64 encoded |
| Security | IMDSv2 enforced (`http_tokens = "required"`), EBS volume encrypted by default |
| Monitoring | Detailed CloudWatch monitoring enabled (1 min resolution) |

### 2. Auto Scaling Group (`aws_autoscaling_group.this`)

| Parameter | Variable | Default |
|---|---|---|
| Min capacity | `min_size` | 2 |
| Max capacity | `max_size` | 6 |
| Desired capacity | `desired_capacity` | 2 |
| Distribution | `vpc_zone_identifiers` (Multi-AZ, private subnets) | — |
| Health check | `health_check_type` | `EC2` (or `ELB` if behind a load balancer) |

### 3. Scaling Policies

- **Scale-out:** `+1` instance (`scale_out_adjustment`), triggered by high CPU alarm.
- **Scale-in:** `-1` instance (`scale_in_adjustment`), triggered by low CPU alarm.
- **Cooldown:** 300s default between actions to prevent flapping.

### 4. CloudWatch Alarms

| Alarm | Condition | Action |
|---|---|---|
| `cpu-high` | Average CPU > 70% for 5 periods of 60s | Triggers `scale_out` (+ SNS notification) |
| `cpu-low` | Average CPU < 30% for 5 periods of 60s | Triggers `scale_in` (+ SNS notification) |
| `unhealthy-hosts` | Healthy instances < minimum capacity | SNS notification only |

Thresholds and durations can be configured via `scale_out_cpu_threshold`,
`scale_in_cpu_threshold`, `evaluation_periods`, and `period_seconds`.

## Key Variables

See `variables.tf` for the complete list. The most important ones:

```hcl
project_name              = "iac-aws-project"
environment                = "dev"
ami_id                      = "ami-xxxxxxxx"
instance_type               = "t3.micro"
iam_instance_profile_name   = "ec2-app-profile"
security_group_ids          = ["sg-xxxxxxxx"]
vpc_zone_identifiers         = ["subnet-aaa", "subnet-bbb"]
min_size                    = 2
max_size                    = 6
desired_capacity             = 2
sns_topic_arn                = "arn:aws:sns:eu-west-1:xxxx:alerts"
```

## Usage

```hcl
module "app_asg" {
  source = "../../modules/asg"

  project_name              = "iac-aws-project"
  environment                = "dev"
  ami_id                      = data.aws_ami.amazon_linux_2023.id
  iam_instance_profile_name   = module.iam.ec2_instance_profile_name
  security_group_ids          = [module.network.app_security_group_id]
  vpc_zone_identifiers         = module.network.private_subnet_ids
  sns_topic_arn                = module.alerting.sns_topic_arn
}
```

See `example-usage.tf` for a complete example, including user-data that
installs the CloudWatch Agent and `stress-ng` (required for load testing).

## Load Testing Validation Criteria

The script `scripts/stress-test.sh` automates validation of the final
acceptance criterion:

```bash
./scripts/stress-test.sh <asg-name> <duration-in-seconds>
```

Process:
1. Retrieves initial ASG state (capacity, instances).
2. Sends an SSM command (`stress-ng --cpu 0 --cpu-load 90`) to each instance
   to generate sustained CPU load.
3. Monitors in a loop the average `CPUUtilization` and `DesiredCapacity` of the ASG
   every 30s.
4. Provides commands to view alarm history (`describe-alarm-history`) and confirm that:
   - scale-out was triggered after exceeding the high threshold,
   - scale-in was triggered after returning below the low threshold and respecting cooldown.

**Prerequisites:** AWS CLI configured, IAM permissions on `autoscaling`, `ec2`,
`cloudwatch`, `ssm`, and `stress-ng` installed on instances (see
user-data in `example-usage.tf`).

## Considerations / Known Limitations

- **Memory-based scaling not included:** EC2 does not natively expose memory metrics.
  For RAM-triggered scaling, you would need to publish a custom metric via CloudWatch Agent,
  then create a dedicated alarm and policy (outside the scope of this US).
- **`target_group_arns`** is defined in the module but remains empty until
  an Application/Network Load Balancer is deployed in front of the ASG.
- Default thresholds (70% / 30%) are a starting point; adjust based on
  actual load profiles observed in dev/staging environments before production deployment.

## Suggested Next Steps

- Add an ALB + Target Group module to switch `health_check_type`
  to `ELB` and leverage application-level health checks.
- Publish a custom memory metric via CloudWatch Agent for combined CPU + memory scaling.
- Add this module to CloudWatch dashboards (US 4.1) to visualize
  `GroupDesiredCapacity`, `GroupInServiceInstances`, and scaling history.