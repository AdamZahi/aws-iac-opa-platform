variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnets"
  type        = bool
  default     = true
}