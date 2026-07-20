output "dashboard_name" {
  description = "Nom du dashboard CloudWatch créé"
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_arn" {
  description = "ARN du dashboard CloudWatch"
  value       = aws_cloudwatch_dashboard.this.dashboard_arn
}

output "dashboard_url" {
  description = "URL directe vers le dashboard dans la console AWS"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}
