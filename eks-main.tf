provider "aws" {
  region = "us-west-2"
}

# Declare a data resource to get available availability zones
data "aws_availability_zones" "available" {}

# IAM Role for EKS
resource "aws_iam_role" "eks_role" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach IAM Policy to the Role
resource "aws_iam_role_policy_attachment" "eks_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

# EKS Cluster Resource
resource "aws_eks_cluster" "app_eks" {
  name     = "my-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = aws_subnet.app_subnet[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_policy_attachment]
}

# VPC Resource
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Subnet Resource
resource "aws_subnet" "app_subnet" {
  count             = 2
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "app_subnet_${count.index}"
  }
}

# Security Group Resource
resource "aws_security_group" "app_sg" {
  name   = "app_security_group"
  vpc_id = aws_vpc.app_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app_security_group"
  }
}

# EKS Node Group for Compute Nodes
resource "aws_eks_node_group" "compute_nodes" {
  cluster_name    = aws_eks_cluster.app_eks.name
  node_group_name = "compute-nodes"
  node_role_arn   = aws_iam_role.eks_role.arn
  subnet_ids      = aws_subnet.app_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["c5.large"]
}

# EKS Node Group for Memory Nodes
resource "aws_eks_node_group" "memory_nodes" {
  cluster_name    = aws_eks_cluster.app_eks.name
  node_group_name = "memory-nodes"
  node_role_arn   = aws_iam_role.eks_role.arn
  subnet_ids      = aws_subnet.app_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["r5.large"]
}

# EKS Node Group for Storage Nodes
resource "aws_eks_node_group" "storage_nodes" {
  cluster_name    = aws_eks_cluster.app_eks.name
  node_group_name = "storage-nodes"
  node_role_arn   = aws_iam_role.eks_role.arn
  subnet_ids      = aws_subnet.app_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["i3.large"]
}

# WAF Web ACL Resource
resource "aws_wafv2_web_acl" "app_web_acl" {
  name        = "app-web-acl"
  scope       = "REGIONAL"
  description = "Web ACL for the application"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-web-acl"
    sampled_requests_enabled    = true
  }

  rule {
    name     = "example-rule"
    priority = 1

    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = "example-header"  # Header names must be lowercase
          }
        }

        positional_constraint = "CONTAINS"
        search_string        = "example"

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "example-rule"
      sampled_requests_enabled    = true
    }
  }
}

# S3 Bucket Resource
resource "aws_s3_bucket" "app_bucket" {
  bucket = "my-app-bucket"
}

# CloudFront Distribution Resource
resource "aws_cloudfront_distribution" "app_distribution" {
  origin {
    domain_name = aws_s3_bucket.app_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }

  default_cache_behavior {
    target_origin_id = "S3Origin"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"  # Updated to include cookies block
      }
    }

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  enabled = true

  viewer_certificate {
    cloudfront_default_certificate = true  # Added viewer_certificate block
  }
}

# Output for Cluster Security Group ID
output "cluster_security_group_id" {
  value = aws_security_group.app_sg.id  # Now this resource is declared
}
