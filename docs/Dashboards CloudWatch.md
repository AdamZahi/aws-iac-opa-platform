# US 7 - CloudWatch Dashboards

**Epic:** Monitoring & Observability
**Status:** Implemented
**Type:** Reusable Terraform module

## Goal

As a Cloud operator, create CloudWatch dashboards to monitor the health and
performance of resources in real time: CPU, memory, network, and disk.

## Structure

```
modules/cloudwatch-dashboard/
├── main.tf                           # Dashboard construction (JSON widgets)
├── variables.tf                      # Module input variables
├── outputs.tf                        # Dashboard name, ARN, and console URL
├── example-usage.tf                  # Usage example + user-data integration
└── files/
    └── cloudwatch-agent-config.json  # CloudWatch Agent config (memory/disk)
```

## Why the CloudWatch Agent is required

AWS/EC2 natively exposes `CPUUtilization`, `NetworkIn`, and `NetworkOut`, but
**not** memory or disk usage. Those are operating-system-level metrics that AWS
cannot observe from the hypervisor. To collect them, the **CloudWatch Agent**
must be installed on each instance and publish metrics to the custom namespace
`CWAgent`.

That is why this module provides `files/cloudwatch-agent-config.json`, to be
deployed through the Launch Template `user_data` in the `asg` module.

## Implemented components

### Dashboard (`aws_cloudwatch_dashboard.this`)

A single dashboard named `${project_name}-${environment}-observability`,
organized into widget rows:

| Row | Content | Namespace |
|---|---|---|
| 1 | ASG capacity (desired / in service / min / max) | `AWS/AutoScaling` |
| 2 | **CPU** - ASG average + per-instance detail | `AWS/EC2` |
| 3 | **Network** - NetworkIn / NetworkOut, ASG average + per-instance detail | `AWS/EC2` |
| 4 | **Memory** and **Disk** usage (%), per instance | `CWAgent` |
| 5 (optional) | RDS - CPU, connections, storage, latency | `AWS/RDS` |
| 6 (optional) | ALB - requests, 5XX errors, response time | `AWS/ApplicationELB` |

The RDS and ALB sections are added only when `rds_instance_identifier` or
`alb_arn_suffix` is set, so the dashboard stays relevant in environments
without a database or load balancer.

Each CPU / Network / Memory / Disk widget shows both the ASG-level aggregate
and the per-instance breakdown (`instance_ids`) so it is easier to spot a
single instance that is behaving differently from the rest of the group.

## Main variables

See `variables.tf` for the full list. The most important ones are:

```hcl
project_name = "iac-aws-project"
environment  = "dev"
aws_region   = "eu-west-1"

asg_name     = module.app_asg.asg_name
instance_ids = data.aws_instances.app.ids

rds_instance_identifier = module.database.rds_instance_identifier
alb_arn_suffix          = module.load_balancer.alb_arn_suffix

enable_cloudwatch_agent_metrics = true
disk_device                     = "xvda1"
disk_fstype                     = "xfs"
```

## Usage

```hcl
module "observability_dashboard" {
  source = "../../modules/cloudwatch-dashboard"

  project_name = "iac-aws-project"
  environment  = "dev"
  aws_region   = "eu-west-1"

  asg_name     = module.app_asg.asg_name
  instance_ids = data.aws_instances.app.ids
}
```

See `example-usage.tf` for the complete example, including the `aws_instances`
data source used to fetch the current ASG instances dynamically as the group
scales.

## Deploying the CloudWatch Agent

Two prerequisites are required for the Memory/Disk widgets to show data:

1. **IAM**: the instance profile (`iam_instance_profile_name` from the `asg`
   module) must include the managed policy `CloudWatchAgentServerPolicy` (or an
   equivalent least-privilege role allowing `cloudwatch:PutMetricData` and
   SSM Parameter Store access if the config is distributed through SSM).
2. **User data**: install and start the CloudWatch Agent with the provided
   configuration file. Example to add to the `asg` module `user_data`:

   ```bash
   #!/bin/bash
   dnf install -y amazon-cloudwatch-agent
   mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
   cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
   ${file("../cloudwatch-dashboard/files/cloudwatch-agent-config.json")}
   EOF
   /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
     -a fetch-config -m ec2 -s \
     -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
   ```

Without this step, the dashboard's Memory and Disk widgets will remain empty
(no data in the `CWAgent` namespace), even if the dashboard itself is deployed
correctly.

## Validation / Runbook

1. Deploy the module (`terraform apply`) and retrieve the `dashboard_url`
   output.
2. Open the dashboard in the AWS Console and confirm that the 4 CPU / Network /
   Memory / Disk rows show data for each instance currently running in the ASG.
3. If Memory / Disk are still empty, verify that the CloudWatch Agent is running
   on the instance (`systemctl status amazon-cloudwatch-agent`) and that the IAM
   role allows `cloudwatch:PutMetricData`.
4. Optional: run `scripts/stress_test.sh` from the `asg` module to observe the
   CPU widget change in real time and see how the ASG Capacity widget reacts.

## Notes and known limitations

- **`instance_ids` is a static list** at `plan` / `apply` time. If the ASG
  scales between deployments, the list may become stale. The `aws_instances`
  data source in `example-usage.tf` reduces this problem by recalculating the
  list on each `apply`, but the dashboard does not update in real time between
  applies (a native limitation of `aws_cloudwatch_dashboard`, which is not
  dynamic at runtime from Terraform's perspective). A possible alternative is
  to rely only on metric math / grouping by `AutoScalingGroupName` (already used
  for the aggregated CPU / Network widgets) and treat per-instance detail as
  best effort.
- **Cost**: custom CloudWatch dashboards are billed per dashboard per month
  beyond the free tier (3 free dashboards). Mention this in the FinOps ticket if
  multiple environments are deployed.
- **Scope**: this ticket covers visualization only; it does not create alarms
  (see US 6.1 for ASG-related CPU alarms). Dedicated Memory / Disk alarms could
  be added in a follow-up ticket if needed.

## Suggested next steps

- Add CloudWatch alarms on `mem_used_percent` and `disk_used_percent` (today,
  only CPU is covered by an alarm through the `asg` module).
- Add a "logs" widget (Contributor Insights or Logs Insights) once CloudTrail
  / CloudWatch Logs centralization is in place.
- Export the dashboard as a separately versioned JSON file if multiple teams
  need to customize it without going through Terraform (an ops-friendly vs.
  strict Infrastructure-as-Code tradeoff to decide as a team).
