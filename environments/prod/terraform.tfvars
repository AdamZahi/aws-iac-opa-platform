aws_region           = "eu-west-2"
project_name         = "pipeline"
environment          = "prod"

# Separate CIDR, no overlap with dev or staging
vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
availability_zones   = ["eu-west-2a", "eu-west-2b"]

# Production-grade instances
ec2_instance_type    = "t3.medium"
db_instance_class    = "db.t3.medium"

db_username          = "admin"
db_password          = "changeme_prod"