variable "project_name" {
  type = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be 'dev', 'staging' or 'prod'."
  }
}

variable "tags" {
  description = "Tags communs appliqués à toutes les ressources"
  type        = map(string)
  default     = {}
}

# Launch Template

variable "ami_id" {
  description = "ID de l'AMI utilisée pour les instances EC2"
  type        = string
}

variable "instance_type" {
  description = "Type d'instance EC2 (ex: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nom de la key pair SSH (optionnel, laisser vide si accès via SSM uniquement)"
  type        = string
  default     = null
}

variable "iam_instance_profile_name" {
  description = "Nom du profil d'instance IAM à associer (rôle least-privilege)"
  type        = string
}

variable "security_group_ids" {
  description = "Liste des Security Group IDs à associer aux instances"
  type        = list(string)
}

variable "user_data" {
  description = "Script user-data (déjà encodé en base64 par l'appelant, ou utiliser base64encode())"
  type        = string
  default     = ""
}

variable "ebs_volume_size" {
  description = "Taille du volume EBS root en Go"
  type        = number
  default     = 20
}

variable "ebs_volume_type" {
  description = "Type de volume EBS root"
  type        = string
  default     = "gp3"
}

variable "ebs_encrypted" {
  description = "Chiffrement du volume EBS root"
  type        = bool
  default     = true
}

# Auto Scaling Group

variable "vpc_zone_identifiers" {
  description = "Liste des subnet IDs (privés) où déployer les instances, répartis multi-AZ"
  type        = list(string)
}

variable "min_size" {
  description = "Capacité minimale de l'ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Capacité maximale de l'ASG"
  type        = number
  default     = 6
}

variable "desired_capacity" {
  description = "Capacité souhaitée de l'ASG au démarrage"
  type        = number
  default     = 2
}

variable "health_check_type" {
  description = "Type de health check pour l'ASG (EC2 ou ELB)"
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type doit être 'EC2' ou 'ELB'."
  }
}

variable "health_check_grace_period" {
  description = "Délai (en secondes) avant le premier health check après le lancement d'une instance"
  type        = number
  default     = 300
}

variable "target_group_arns" {
  description = "Liste des ARNs des Target Groups (si utilisé derrière un ALB/NLB)"
  type        = list(string)
  default     = []
}

# Scaling Policies / CloudWatch Alarms

variable "scale_out_cpu_threshold" {
  description = "Seuil de CPU (%) déclenchant un scale-out"
  type        = number
  default     = 70
}

variable "scale_in_cpu_threshold" {
  description = "Seuil de CPU (%) déclenchant un scale-in"
  type        = number
  default     = 30
}

variable "evaluation_periods" {
  description = "Nombre de périodes consécutives avant déclenchement de l'alarme"
  type        = number
  default     = 5
}

variable "period_seconds" {
  description = "Durée (en secondes) de chaque période d'évaluation CloudWatch"
  type        = number
  default     = 60
}

variable "scale_out_adjustment" {
  description = "Nombre d'instances ajoutées lors d'un scale-out"
  type        = number
  default     = 1
}

variable "scale_in_adjustment" {
  description = "Nombre d'instances retirées lors d'un scale-in (valeur négative)"
  type        = number
  default     = -1
}

variable "scaling_cooldown" {
  description = "Période de cooldown (en secondes) entre deux actions de scaling"
  type        = number
  default     = 300
}

variable "sns_topic_arn" {
  description = "ARN du topic SNS pour les notifications d'alarme (Slack/email via SNS subscription)"
  type        = string
  default     = null
}
