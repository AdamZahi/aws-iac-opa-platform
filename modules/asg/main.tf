locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

# Launch Template

resource "aws_launch_template" "this" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = var.user_data != "" ? base64encode(var.user_data) : null

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.ebs_volume_size
      volume_type            = var.ebs_volume_type
      encrypted              = var.ebs_encrypted
      delete_on_termination  = true
    }
  }

  monitoring {
    enabled = true # active le monitoring détaillé CloudWatch (1 min au lieu de 5 min)
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatoire (bonne pratique sécurité)
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-volume"
    })
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group

resource "aws_autoscaling_group" "this" {
  name                      = "${local.name_prefix}-asg"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.vpc_zone_identifiers
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  target_group_arns         = var.target_group_arns

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Répartition équilibrée entre les AZ définies dans vpc_zone_identifiers
  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name_prefix}-instance" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Scaling Policies

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${local.name_prefix}-scale-out"
  scaling_adjustment     = var.scale_out_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scaling_cooldown
  autoscaling_group_name = aws_autoscaling_group.this.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${local.name_prefix}-scale-in"
  scaling_adjustment     = var.scale_in_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scaling_cooldown
  autoscaling_group_name = aws_autoscaling_group.this.name
}

# CloudWatch Alarms driving the scaling policies

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.period_seconds
  statistic           = "Average"
  threshold           = var.scale_out_cpu_threshold
  alarm_description   = "CPU moyen > ${var.scale_out_cpu_threshold}% pendant ${var.evaluation_periods * var.period_seconds / 60} min -> scale-out"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = compact([
    aws_autoscaling_policy.scale_out.arn,
    var.sns_topic_arn
  ])

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.period_seconds
  statistic           = "Average"
  threshold           = var.scale_in_cpu_threshold
  alarm_description   = "CPU moyen < ${var.scale_in_cpu_threshold}% pendant ${var.evaluation_periods * var.period_seconds / 60} min -> scale-in"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = compact([
    aws_autoscaling_policy.scale_in.arn,
    var.sns_topic_arn
  ])

  tags = local.common_tags
}

# Alarme complémentaire : nombre d'instances saines (détection de dégradation)
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-unhealthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Minimum"
  threshold           = var.min_size
  alarm_description   = "Le nombre d'instances saines est inférieur à la capacité minimale attendue"
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  alarm_actions = compact([var.sns_topic_arn])

  tags = local.common_tags
}
