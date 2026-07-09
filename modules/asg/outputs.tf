output "launch_template_id" {
  description = "ID du Launch Template créé"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Dernière version du Launch Template"
  value       = aws_launch_template.this.latest_version
}

output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN de l'Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

output "scale_out_policy_arn" {
  description = "ARN de la politique de scale-out"
  value       = aws_autoscaling_policy.scale_out.arn
}

output "scale_in_policy_arn" {
  description = "ARN de la politique de scale-in"
  value       = aws_autoscaling_policy.scale_in.arn
}

output "cpu_high_alarm_arn" {
  description = "ARN de l'alarme CloudWatch CPU haute"
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn
}

output "cpu_low_alarm_arn" {
  description = "ARN de l'alarme CloudWatch CPU basse"
  value       = aws_cloudwatch_metric_alarm.cpu_low.arn
}
