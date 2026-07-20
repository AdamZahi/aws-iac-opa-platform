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

# Backup Vault
# Stocke toutes les sauvegardes (RDS snapshots, EBS/EC2 snapshots) de manière centralisée, chiffrée, avec une politique d'accès dédiée.

resource "aws_backup_vault" "this" {
  name = "${local.name_prefix}-backup-vault"
  tags = local.common_tags
}

resource "aws_backup_vault_notifications" "this" {
  count = var.sns_topic_arn != null ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name
  sns_topic_arn     = var.sns_topic_arn
  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "BACKUP_JOB_EXPIRED",
    "RESTORE_JOB_FAILED",
  ]
}

# Vault Lock : optionnel, empêche la suppression prématurée des sauvegardes même par un compte admin, une fois en mode "compliance" (irréversible).
resource "aws_backup_vault_lock_configuration" "this" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name  = aws_backup_vault.this.name
  min_retention_days = var.vault_lock_min_retention_days
  max_retention_days = var.vault_lock_max_retention_days
}

# IAM Role pour AWS Backup
data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${local.name_prefix}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
  tags               = local.common_tags
}

# Policies managées AWS dédiées au service Backup (least-privilege : accès
# limité aux actions de sauvegarde/restauration, pas d'accès applicatif).
resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup Plan : couvre RDS et EC2/EBS via un plan unifié

resource "aws_backup_plan" "this" {
  name = "${local.name_prefix}-backup-plan"

  # Règle quotidienne : rétention courte, pour restauration rapide
  rule {
    rule_name         = "daily-backups"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.daily_backup_schedule
    start_window      = var.backup_start_window_minutes
    completion_window = var.backup_completion_window_minutes

    lifecycle {
      delete_after        = var.daily_retention_days
      cold_storage_after  = var.cold_storage_after_days > 0 ? var.cold_storage_after_days : null
    }

    recovery_point_tags = merge(local.common_tags, {
      BackupFrequency = "daily"
    })
  }

  # Règle hebdomadaire : rétention plus longue, pour couvrir les incidents
  # détectés tardivement (ex: suppression accidentelle découverte 2 semaines après)
  rule {
    rule_name         = "weekly-backups"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.weekly_backup_schedule
    start_window      = var.backup_start_window_minutes
    completion_window = var.backup_completion_window_minutes

    lifecycle {
      delete_after       = var.weekly_retention_days
      cold_storage_after = var.cold_storage_after_days > 0 ? var.cold_storage_after_days : null
    }

    recovery_point_tags = merge(local.common_tags, {
      BackupFrequency = "weekly"
    })
  }

  tags = local.common_tags
}

# Backup Selection : quelles ressources sont couvertes par le plan
# Sélection par tag : toute ressource RDS/EC2/EBS taguée Backup=true est
# automatiquement incluse, sans modification du plan Terraform. Complétée
# par une liste optionnelle d'ARNs explicites pour les cas particuliers.

resource "aws_backup_selection" "this" {
  name         = "${local.name_prefix}-backup-selection"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = var.additional_resource_arns

  condition {
    string_equals {
      key   = "aws:ResourceTag/${var.backup_selection_tag_key}"
      value = var.backup_selection_tag_value
    }
  }
}

# Alarme CloudWatch : jobs de backup en échec
# Complète les notifications du vault (event-driven) par une alarme
# CloudWatch classique, pour homogénéité avec le reste du projet (US 4.1 / 6.1).

resource "aws_cloudwatch_metric_alarm" "backup_job_failed" {
  alarm_name          = "${local.name_prefix}-backup-job-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Au moins un job AWS Backup a échoué au cours de la dernière heure"

  alarm_actions = compact([var.sns_topic_arn])
  tags = local.common_tags
}
