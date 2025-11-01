# 1 Terraform configuration and provider

terraform {
    backend "s3" {
        bucket         = "mon-terraform-state-bucket"
        key            = "3-tier-architecture/dev/terraform.tfstate"
        region        = "us-west-1"
        dynamodb_table = "mon-terraform-lock-table"
        encrypt        = true
    }
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

provider "aws" {
  region = "us-west-1"
}


# 2 Networking and configuring subnets and vpc 

# find the default vpc in my account 

data "aws_vpc" "default" {
  default = true
}

# find the default subnets in my account
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}


# Security Groups virtual firewall  for our instances
resource "aws_security_group" "instances" {
  name = "security-group-instances" 
}

# allowing http trafic to our instances 
resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  from_port        = 8080
  to_port          = 8080
  security_group_id = aws_security_group.instances.id
  protocol         = "tcp"
  cidr_blocks     = ["0.0.0.0/0"] 
}


# allowing http trafiic inbound and outbount to our load balencer 
resource "aws_security_group" "load_balancer" {
  name = "security-group-load-balancer" 
}

resource "aws_security_group_rule" "allow_http_inbound_lb" {
  type              = "ingress"
  from_port        = 80
  to_port          = 80
  security_group_id = aws_security_group.load_balancer.id
  protocol         = "tcp"
  cidr_blocks     = ["0.0.0.0/0"] 
}

resource "aws_security_group_rule" "allow_http_outbound_lb" {
  type              = "egress"
  from_port        = 0
  to_port          = 0
  security_group_id = aws_security_group.load_balancer.id
  protocol         = "-1"
  cidr_blocks     = ["0.0.0.0/0"] 
}

# setuping the ec2 instances 
resource "aws_instance" "instance_1" {
  ami               = "ami-011899242bb902164" # Ubuntu 20.04 LTS
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.instances.name]
  user_data         = <<-EOF
              #!/bin/bash
              echo "Hello, World 1" > index.html
              python3 -m http.server 8080 & # Starts web server
              EOF
}

resource "aws_instance" "instance_2" {
  ami               = "ami-011899242bb902164" # Ubuntu 20.04 LTS
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.instances.name]
  user_data         = <<-EOF
              #!/bin/bash
              echo "Hello, World 2" > index.html
              python3 -m http.server 8080 & # Starts web server
              EOF
}

# setting up the load balancer target group 
resource "aws_lb_target_group" "instances" {
  name     = "app-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
} 

# creation of the load balancer
resource "aws_lb" "web_load_balancer" {
  name               = "app-load-balancer"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer.id]
  subnets            = data.aws_subnet_ids.default.ids
}

# attach the two instacens to the load balencer 
resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_2.id
  port             = 8080
}

# add listen to the load balencer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# adding listner rule to the target group 
resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"] # Match all paths
    }
  }

  action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.instances.arn
  }
}


# S3 bucket to store application data
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "devops-directive-web-app-data"
  force_destroy = true
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# setup encryption for the s3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_crypto_conf" {
  bucket = aws_s3_bucket.bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# RDS Postgres Database Instance

resource "aws_db_instance" "db_instance" {
  allocated_storage          = 20
  auto_minor_version_upgrade = true
  storage_type               = "standard"
  engine                     = "postgres"
  engine_version             = "12"
  instance_class             = "db.t2.micro"
  identifier                 = "mydb"
  username                   = "foo"
  password                   = "foobarbaz"
  skip_final_snapshot        = true
}


# Create the Route 53 Hosted Zone
resource "aws_route53_zone" "primary" {
  name = "devopsdeployed.com"
}

# Create the A record to point the domain to the Load Balancer
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "devopsdeployed.com"
  type    = "A"

  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }
}
