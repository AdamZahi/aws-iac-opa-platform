locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  dashboard_name = "${local.name_prefix}-observability"

  # ---------------------------------------------------------------------------
  # Metric builders
  # ---------------------------------------------------------------------------
  # Chaque instance individuelle est ajoutée en plus de la moyenne ASG, pour
  # pouvoir repérer une instance qui dévierait du groupe.

  cpu_metrics = concat(
    [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "ASG - Moyenne" }]],
    [for id in var.instance_ids : ["AWS/EC2", "CPUUtilization", "InstanceId", id, { stat = "Average", label = id }]]
  )

  network_in_metrics = concat(
    [["AWS/EC2", "NetworkIn", "AutoScalingGroupName", var.asg_name, { stat = "Sum", label = "ASG - NetworkIn" }]],
    [for id in var.instance_ids : ["AWS/EC2", "NetworkIn", "InstanceId", id, { stat = "Sum", label = "${id} - In" }]]
  )

  network_out_metrics = concat(
    [["AWS/EC2", "NetworkOut", "AutoScalingGroupName", var.asg_name, { stat = "Sum", label = "ASG - NetworkOut" }]],
    [for id in var.instance_ids : ["AWS/EC2", "NetworkOut", "InstanceId", id, { stat = "Sum", label = "${id} - Out" }]]
  )

  # Mémoire et disque proviennent du namespace custom "CWAgent" (CloudWatch Agent),
  # ces métriques ne sont pas disponibles nativement dans AWS/EC2.
  memory_metrics = [
    for id in var.instance_ids : [
      "CWAgent", "mem_used_percent", "InstanceId", id,
      { stat = "Average", label = id }
    ]
  ]

  disk_metrics = [
    for id in var.instance_ids : [
      "CWAgent", "disk_used_percent", "InstanceId", id, "device", var.disk_device, "fstype", var.disk_fstype, "path", var.disk_path,
      { stat = "Average", label = id }
    ]
  ]

  asg_capacity_metrics = [
    ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "Désirée" }],
    ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "En service" }],
    ["AWS/AutoScaling", "GroupMinSize", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "Min" }],
    ["AWS/AutoScaling", "GroupMaxSize", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "Max" }],
  ]

  rds_widgets = var.rds_instance_identifier != "" ? [
    {
      type   = "metric"
      x      = 0
      y      = 100
      width  = 12
      height = 6
      properties = {
        title  = "RDS - CPU & Connexions"
        region = var.aws_region
        period = var.dashboard_period_seconds
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "CPU %" }],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "Connexions", yAxis = "right" }],
        ]
        view = "timeSeries"
        yAxis = {
          left  = { min = 0, max = 100 }
          right = { min = 0 }
        }
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 100
      width  = 12
      height = 6
      properties = {
        title  = "RDS - Stockage & Latence"
        region = var.aws_region
        period = var.dashboard_period_seconds
        metrics = [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "Stockage libre" }],
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "Latence lecture", yAxis = "right" }],
          ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "Latence écriture", yAxis = "right" }],
        ]
        view = "timeSeries"
      }
    }
  ] : []

  alb_widgets = var.alb_arn_suffix != "" ? [
    {
      type   = "metric"
      x      = 0
      y      = 112
      width  = 24
      height = 6
      properties = {
        title  = "ALB - Requêtes & Erreurs"
        region = var.aws_region
        period = var.dashboard_period_seconds
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Requêtes" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Erreurs 5XX" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "Temps de réponse", yAxis = "right" }],
        ]
        view = "timeSeries"
      }
    }
  ] : []

  base_widgets = [
    # Ligne 1 : capacité ASG (contexte global)
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 24
      height = 6
      properties = {
        title   = "Auto Scaling Group - Capacité"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = local.asg_capacity_metrics
        view    = "timeSeries"
        stacked = false
      }
    },
    # Ligne 2 : CPU
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 24
      height = 6
      properties = {
        title   = "CPU Utilization (%)"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = local.cpu_metrics
        view    = "timeSeries"
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    # Ligne 3 : Réseau (in / out côte à côte)
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "Network In (bytes)"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = local.network_in_metrics
        view    = "timeSeries"
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "Network Out (bytes)"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = local.network_out_metrics
        view    = "timeSeries"
      }
    },
  ]

  cwagent_widgets = var.enable_cloudwatch_agent_metrics ? [
    # Ligne 4 : Mémoire
    {
      type   = "metric"
      x      = 0
      y      = 18
      width  = 12
      height = 6
      properties = {
        title   = "Mémoire utilisée (%) — via CloudWatch Agent"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = length(local.memory_metrics) > 0 ? local.memory_metrics : [["CWAgent", "mem_used_percent"]]
        view    = "timeSeries"
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    # Ligne 4 : Disque
    {
      type   = "metric"
      x      = 12
      y      = 18
      width  = 12
      height = 6
      properties = {
        title   = "Disque utilisé (%) — via CloudWatch Agent"
        region  = var.aws_region
        period  = var.dashboard_period_seconds
        metrics = length(local.disk_metrics) > 0 ? local.disk_metrics : [["CWAgent", "disk_used_percent"]]
        view    = "timeSeries"
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
  ] : []

  dashboard_body = {
    widgets = concat(
      local.base_widgets,
      local.cwagent_widgets,
      local.rds_widgets,
      local.alb_widgets,
    )
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode(local.dashboard_body)
}
