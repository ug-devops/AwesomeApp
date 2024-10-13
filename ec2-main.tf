provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "app-vpc" }
}

# Internet Gateway
resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id
  tags = { Name = "app-igw" }
}

# Route Table
resource "aws_route_table" "app_route_table" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }
  tags = { Name = "app-route-table" }
}

# Subnet
resource "aws_subnet" "app_subnet" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "app-subnet" }
}

# Route Table Association
resource "aws_route_table_association" "app_rta" {
  subnet_id      = aws_subnet.app_subnet.id
  route_table_id = aws_route_table.app_route_table.id
}

# NAT Gateway
resource "aws_eip" "app_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "app_nat_gateway" {
  allocation_id = aws_eip.app_eip.id
  subnet_id     = aws_subnet.app_subnet.id
  tags = { Name = "app-nat-gateway" }
}

# Security Group
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.app_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "app-sg" }
}

# AWS WAF Web ACL
resource "aws_wafv2_web_acl" "app_waf" {
  name        = "app-waf"
  scope       = "REGIONAL"
  description = "WAF for the application"

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-waf"
    sampled_requests_enabled   = true
  }

  default_action {
    allow {}
  }

  rule {
    name     = "block-bad-actors"
    priority = 1

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    action {
      block {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-bad-actors"
      sampled_requests_enabled   = true
    }
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "app_secret" {
  name        = "app-db-credentials"
  description = "Database credentials for the app"
}

# Application Load Balancer (ALB)
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = [aws_subnet.app_subnet.id]
  tags = { Name = "app-alb" }
}

# ALB Listener
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}

# ALB Target Group
resource "aws_lb_target_group" "app_target_group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id
  health_check {
    path = "/"
  }
}

# S3 Bucket for CloudFront Origin
resource "aws_s3_bucket" "app_bucket" {
  bucket = "my-app-assets-bucket"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "app_cdn" {
  origin {
    domain_name = aws_s3_bucket.app_bucket.bucket_regional_domain_name
    origin_id   = "app-s3-origin"
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "app-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Launch Templates for Compute, Memory, and Storage Instances
resource "aws_launch_template" "compute_template" {
  name          = "compute-launch-template"
  image_id      = "ami-0866a3c8686eaeeba"
  instance_type = "c5.large"
}

resource "aws_launch_template" "memory_template" {
  name          = "memory-launch-template"
  image_id      = "ami-0866a3c8686eaeeba"
  instance_type = "r5.large"
}

resource "aws_launch_template" "storage_template" {
  name          = "storage-launch-template"
  image_id      = "ami-0866a3c8686eaeeba"
  instance_type = "i3.large"
}

# Autoscaling Groups for Instances
resource "aws_autoscaling_group" "compute_asg" {
  launch_template { id = aws_launch_template.compute_template.id }
  vpc_zone_identifier = [aws_subnet.app_subnet.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2
}

resource "aws_autoscaling_group" "memory_asg" {
  launch_template { id = aws_launch_template.memory_template.id }
  vpc_zone_identifier = [aws_subnet.app_subnet.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2
}

resource "aws_autoscaling_group" "storage_asg" {
  launch_template { id = aws_launch_template.storage_template.id }
  vpc_zone_identifier = [aws_subnet.app_subnet.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2
}
