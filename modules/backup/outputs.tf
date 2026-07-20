output "backup_vault_name" {
  description = "Nom du Backup Vault"
  value       = aws_backup_vault.this.name
}

output "backup_vault_arn" {
  description = "ARN du Backup Vault"
  value       = aws_backup_vault.this.arn
}

output "backup_plan_id" {
  description = "ID du plan de backup"
  value       = aws_backup_plan.this.id
}

output "backup_plan_arn" {
  description = "ARN du plan de backup"
  value       = aws_backup_plan.this.arn
}

output "backup_role_arn" {
  description = "ARN du rôle IAM utilisé par AWS Backup"
  value       = aws_iam_role.backup.arn
}

output "backup_selection_tag" {
  description = "Tag clé/valeur à appliquer aux ressources pour qu'elles soient sauvegardées automatiquement"
  value       = "${var.backup_selection_tag_key}=${var.backup_selection_tag_value}"
}

output "rds_native_backup_settings" {
  description = "Paramètres à passer au module RDS pour activer les sauvegardes automatiques natives (point-in-time recovery)"
  value = var.enable_rds_native_backups ? {
    backup_retention_period = var.rds_backup_retention_period
    backup_window            = var.rds_backup_window
  } : null
}
