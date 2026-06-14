terraform {
  backend "s3" {
    bucket         = "terraform-iac-project-state"
    key            = "staging/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}