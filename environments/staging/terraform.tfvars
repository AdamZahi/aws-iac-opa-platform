aws_region           = "eu-west-2"
project_name         = "adam-zahi"
environment          = "staging"

# Slightly larger CIDR space, no overlap with dev
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
availability_zones   = ["eu-west-2a", "eu-west-2b"]

# Bigger instances than dev
ec2_instance_type    = "t3.small"
db_instance_class    = "db.t3.small"

db_username          = "admin"
db_password          = "admin1234"