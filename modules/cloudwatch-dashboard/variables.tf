# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Nom du projet, utilisé pour le nommage du dashboard"
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

variable "aws_region" {
  description = "Région AWS utilisée dans les widgets du dashboard"
  type        = string
}

# -----------------------------------------------------------------------------
# Target resources
# -----------------------------------------------------------------------------

variable "asg_name" {
  description = "Nom de l'Auto Scaling Group à surveiller (issu du module asg)"
  type        = string
}

variable "instance_ids" {
  description = "Liste des instance IDs à afficher individuellement (optionnel, en plus des agrégats ASG)"
  type        = list(string)
  default     = []
}

variable "rds_instance_identifier" {
  description = "Identifiant de l'instance RDS à surveiller (laisser vide si pas de RDS)"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "Suffixe d'ARN de l'ALB (format XX/YY/ZZ) à surveiller (laisser vide si pas d'ALB)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudWatch Agent (Memory / Disk)
# -----------------------------------------------------------------------------

variable "enable_cloudwatch_agent_metrics" {
  description = "Active les widgets Mémoire/Disque, qui nécessitent le CloudWatch Agent installé sur les instances"
  type        = bool
  default     = true
}

variable "disk_device" {
  description = "Nom du device disque tel que rapporté par le CloudWatch Agent (ex: xvda1, nvme0n1p1)"
  type        = string
  default     = "xvda1"
}

variable "disk_fstype" {
  description = "Type de filesystem tel que rapporté par le CloudWatch Agent (ex: xfs, ext4)"
  type        = string
  default     = "xfs"
}

variable "disk_path" {
  description = "Point de montage surveillé pour la métrique disk_used_percent"
  type        = string
  default     = "/"
}

# -----------------------------------------------------------------------------
# Dashboard behaviour
# -----------------------------------------------------------------------------

variable "dashboard_period_seconds" {
  description = "Période par défaut (en secondes) des widgets du dashboard"
  type        = number
  default     = 300
}
