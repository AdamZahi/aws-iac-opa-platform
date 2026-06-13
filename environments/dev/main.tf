module "vpc" {
  source      = "../../modules/vpc"
  project_name = "smartovate"
  environment  = "dev"
}

module "ec2" {
  source      = "../../modules/ec2"
  project_name = "smartovate"
  environment  = "dev"
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.private_subnet_ids[0]
}

module "rds" {
  source      = "../../modules/rds"
  project_name = "smartovate"
  environment  = "dev"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.ec2.security_group_id]
  db_username = var.db_username
  db_password = var.db_password
}