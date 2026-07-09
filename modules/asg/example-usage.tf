# Exemple d'appel du module depuis un environnement (ex: environments/dev/main.tf)

module "app_asg" {
  source = "../../modules/asg"

  project_name = "iac-aws-project"
  environment  = "dev"

  ami_id                     = data.aws_ami.amazon_linux_2023.id
  instance_type              = "t3.micro"
  iam_instance_profile_name  = module.iam.ec2_instance_profile_name
  security_group_ids         = [module.network.app_security_group_id]
  vpc_zone_identifiers        = module.network.private_subnet_ids

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y amazon-cloudwatch-agent stress-ng
    systemctl enable amazon-cloudwatch-agent
    systemctl start amazon-cloudwatch-agent
  EOF

  min_size          = 2
  max_size          = 6
  desired_capacity  = 2

  scale_out_cpu_threshold = 70
  scale_in_cpu_threshold  = 30
  evaluation_periods      = 5
  period_seconds          = 60

  sns_topic_arn = module.alerting.sns_topic_arn

  tags = {
    Owner = "cloud-team"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
