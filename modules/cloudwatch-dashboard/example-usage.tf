# -----------------------------------------------------------------------------
# Exemple d'appel du module depuis un environnement (ex: environments/dev/main.tf)
# -----------------------------------------------------------------------------

module "observability_dashboard" {
  source = "../../modules/cloudwatch-dashboard"

  project_name = "iac-aws-project"
  environment  = "dev"
  aws_region   = "eu-west-1"

  asg_name     = module.app_asg.asg_name
  instance_ids = data.aws_instances.app.ids # actualiser périodiquement ou via data source

  rds_instance_identifier = module.database.rds_instance_identifier
  alb_arn_suffix           = module.load_balancer.alb_arn_suffix

  enable_cloudwatch_agent_metrics = true
  disk_device                      = "xvda1"
  disk_fstype                       = "xfs"
}

# Récupère dynamiquement les instances actuelles de l'ASG pour le dashboard
data "aws_instances" "app" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.app_asg.asg_name]
  }

  instance_state_names = ["running"]
}

# -----------------------------------------------------------------------------
# Le user-data du Launch Template (module asg) doit installer et démarrer le
# CloudWatch Agent avec la configuration fournie dans files/cloudwatch-agent-config.json
# pour que les widgets Mémoire et Disque soient alimentés.
# -----------------------------------------------------------------------------
#
# Exemple à ajouter dans le user_data du module "asg" :
#
# #!/bin/bash
# dnf install -y amazon-cloudwatch-agent
# mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
# cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWAGENT_EOF'
# ${file("${path.module}/../cloudwatch-dashboard/files/cloudwatch-agent-config.json")}
# CWAGENT_EOF
# /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
#   -a fetch-config -m ec2 -s \
#   -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
