variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (Amazon Linux 2023 eu-west-2)"
  type        = string
  default     = "ami-0b45ae66668865cd6"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in (use private subnet)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group association"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (leave empty to block all SSH — recommended)"
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach to the EC2 instance"
  type        = string
  default     = null
}

variable "user_data" {
  description = "Optional user data script"
  type        = string
  default     = null
}