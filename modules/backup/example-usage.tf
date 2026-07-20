# -----------------------------------------------------------------------------
# Exemple d'appel du module depuis un environnement (ex: environments/dev/main.tf)
# -----------------------------------------------------------------------------

module "backup" {
  source = "../../modules/backup"

  project_name = "iac-aws-project"
  environment  = "dev"

  backup_selection_tag_key   = "Backup"
  backup_selection_tag_value = "true"

  daily_backup_schedule = "cron(0 3 * * ? *)"  # 03h00 UTC tous les jours
  daily_retention_days  = 7

  weekly_backup_schedule = "cron(0 4 ? * SUN *)" # dimanche 04h00 UTC
  weekly_retention_days  = 28

  sns_topic_arn = module.alerting.sns_topic_arn

  # Vault Lock désactivé par défaut en dev ; à activer en prod une fois
  # la politique de rétention validée (irréversible en mode "compliance")
  enable_vault_lock = false

  tags = {
    Owner = "cloud-team"
  }
}

# -----------------------------------------------------------------------------
# Rattachement des ressources critiques au plan de backup : il suffit de les
# taguer avec Backup=true, la sélection par tag du module s'occupe du reste.
# -----------------------------------------------------------------------------

resource "aws_db_instance" "app" {
  # ... configuration existante de l'instance RDS ...

  # Sauvegardes natives RDS (point-in-time recovery), pilotées par les
  # sorties du module backup pour rester cohérentes avec la politique globale
  backup_retention_period = module.backup.rds_native_backup_settings.backup_retention_period
  backup_window            = module.backup.rds_native_backup_settings.backup_window

  tags = {
    Backup = "true" # inclusion dans le plan AWS Backup (snapshots supplémentaires)
    Name   = "iac-aws-project-dev-db"
  }
}

# Les instances EC2/volumes EBS gérés par l'ASG (module "asg") sont taguées
# automatiquement via les tag_specifications du Launch Template : il suffit
# d'y ajouter Backup=true pour qu'AWS Backup les prenne en charge également.
#
# Exemple d'ajustement dans modules/asg/main.tf (tag_specifications) :
#
#   tags = merge(local.common_tags, {
#     Name   = "${local.name_prefix}-instance"
#     Backup = "true"
#   })
