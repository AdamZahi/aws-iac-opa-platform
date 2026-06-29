aws_region           = "eu-west-2"
project_name         = "iac"
environment          = "dev"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
availability_zones   = ["eu-west-2a", "eu-west-2b"]

ec2_instance_type    = "t3.micro"
db_instance_class    = "db.t3.micro"

# Never commit real values — use env vars or AWS Secrets Manager in CI
db_username          = "admin"
db_password          = "admin1234"