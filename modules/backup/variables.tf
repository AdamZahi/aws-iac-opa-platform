# General
variable "project_name" {
  description = "Nom du projet, utilisé pour le nommage des ressources de backup"
  type        = string
}

variable "environment" {
  description = "Environnement de déploiement (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "L'environnement doit être 'dev', 'staging' ou 'prod'."
  }
}

variable "tags" {
  description = "Tags communs appliqués aux ressources de backup"
  type        = map(string)
  default     = {}
}
# Backup selection (quelles ressources sauvegarder)
variable "backup_selection_tag_key" {
  description = "Clé de tag utilisée pour sélectionner les ressources à sauvegarder via AWS Backup"
  type        = string
  default     = "Backup"
}

variable "backup_selection_tag_value" {
  description = "Valeur de tag utilisée pour sélectionner les ressources à sauvegarder (ex: 'true')"
  type        = string
  default     = "true"
}

variable "additional_resource_arns" {
  description = "ARNs supplémentaires à inclure explicitement dans le plan de backup (en plus de la sélection par tag)"
  type        = list(string)
  default     = []
}
# Schedules & retention policy
variable "daily_backup_schedule" {
  description = "Expression cron (format AWS Backup) pour la sauvegarde quotidienne"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "daily_retention_days" {
  description = "Nombre de jours de rétention pour les sauvegardes quotidiennes"
  type        = number
  default     = 7
}

variable "weekly_backup_schedule" {
  description = "Expression cron (format AWS Backup) pour la sauvegarde hebdomadaire"
  type        = string
  default     = "cron(0 4 ? * SUN *)"
}

variable "weekly_retention_days" {
  description = "Nombre de jours de rétention pour les sauvegardes hebdomadaires"
  type        = number
  default     = 28
}

variable "cold_storage_after_days" {
  description = "Nombre de jours avant transition vers le cold storage (0 = désactivé). Doit être >= 90 si activé (contrainte AWS Backup)"
  type        = number
  default     = 0
}

variable "backup_start_window_minutes" {
  description = "Fenêtre de temps (en minutes) pendant laquelle le job de backup doit démarrer avant d'être considéré en échec"
  type        = number
  default     = 60
}

variable "backup_completion_window_minutes" {
  description = "Fenêtre de temps (en minutes) pendant laquelle le job de backup doit se terminer avant d'être considéré en échec"
  type        = number
  default     = 180
}
# RDS - sauvegardes natives (complément à AWS Backup)
variable "enable_rds_native_backups" {
  description = "Active la configuration des sauvegardes automatiques natives RDS (backup_retention_period) en sortie, pour référence dans le module RDS"
  type        = bool
  default     = true
}

variable "rds_backup_retention_period" {
  description = "Nombre de jours de rétention pour les sauvegardes automatiques natives RDS (point-in-time recovery)"
  type        = number
  default     = 7
}

variable "rds_backup_window" {
  description = "Fenêtre horaire (UTC) pendant laquelle RDS effectue ses sauvegardes automatiques natives"
  type        = string
  default     = "02:00-03:00"
}
# Vault lock (protection contre suppression/modification malveillante)
variable "enable_vault_lock" {
  description = "Active AWS Backup Vault Lock en mode compliance pour empêcher la suppression des sauvegardes avant expiration (irréversible une fois en mode compliance)"
  type        = bool
  default     = false
}

variable "vault_lock_min_retention_days" {
  description = "Rétention minimale imposée par le Vault Lock"
  type        = number
  default     = 7
}

variable "vault_lock_max_retention_days" {
  description = "Rétention maximale imposée par le Vault Lock"
  type        = number
  default     = 90
}
# Notifications
variable "sns_topic_arn" {
  description = "ARN du topic SNS pour les notifications d'échec de backup (Slack/email via SNS subscription)"
  type        = string
  default     = null
}
