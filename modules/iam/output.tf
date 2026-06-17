output "instance_profile_name" {
  description = "IAM instance profile to attach to EC2"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2_ssm.arn
}