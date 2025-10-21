# Terraform project: ALB + ASG with 2 web servers (corrected version)

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDRs (must be in the same region/AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to allow SSH (optional; set to empty string to skip)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to instances"
  type        = string
  default     = "0.0.0.0/0"
}

# Networking
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "tf-alb-asg-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "tf-alb-igw" }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, index(var.public_subnets, each.value))
  tags = { Name = "tf-public-${each.value}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "tf-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Security groups
resource "aws_security_group" "alb_sg" {
  name        = "tf-alb-sg"
  description = "Allow HTTP from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tf-alb-sg" }
}

resource "aws_security_group" "instance_sg" {
  name        = "tf-instance-sg"
  description = "Allow HTTP from ALB and optional SSH"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.key_name != "" ? [var.allowed_ssh_cidr] : []
    description = "SSH (only if key_name provided)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tf-instance-sg" }
}

# ALB and Target Group
resource "aws_lb" "alb" {
  name               = "tf-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = values(aws_subnet.public)[*].id
  tags = { Name = "tf-web-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "tf-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "tf-web-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# AMI + User data
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y nginx
cat > /usr/share/nginx/html/index.html <<'HTML'
<html><head><title>Terraform ALB ASG</title></head>
<body><h1>Hello from $(hostname)</h1><p>Deployed via Terraform</p></body></html>
HTML
systemctl enable nginx
systemctl start nginx
EOF
}

# Launch Template + ASG
resource "aws_launch_template" "web_lt" {
  name_prefix   = "tf-web-lt-"
  image_id      = data.aws_ami.al2.id
  instance_type = var.instance_type
  user_data     = base64encode(local.user_data)

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.instance_sg.id]
  }

  key_name = var.key_name != "" ? var.key_name : null
}

resource "aws_autoscaling_group" "web_asg" {
  name                      = "tf-web-asg"
  max_size                  = 2
  min_size                  = 2
  desired_capacity          = 2
  vpc_zone_identifier       = values(aws_subnet.public)[*].id

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns          = [aws_lb_target_group.web_tg.arn]
  health_check_type          = "ELB"
  health_check_grace_period  = 30

  tag {
    key                 = "Name"
    value               = "tf-web-instance"
    propagate_at_launch = true
  }
}

# Outputs
output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.alb.dns_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}

# Usage:
# terraform init
# terraform plan -out=tfplan
# terraform apply tfplan
# terraform destroy
