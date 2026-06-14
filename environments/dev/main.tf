module "vpc" {
  source               = "../../modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true
}

module "ec2" {
  source        = "../../modules/ec2"
  project_name  = var.project_name
  environment   = var.environment
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_subnet_ids[0]
  instance_type = var.ec2_instance_type
}

module "rds" {
  source                     = "../../modules/rds"
  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.ec2.security_group_id]
  db_username                = var.db_username
  db_password                = var.db_password
  instance_class             = var.db_instance_class
  multi_az                   = false
  skip_final_snapshot        = true
}