terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "my_vm" {
  ami = "ami-0360c520857e3138f" # Amazon Machine Image (AMI) Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
  instance_type = "t3.micro"
}