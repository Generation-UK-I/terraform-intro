# Introduction to Infrastructure as Code (IaC) with Terraform in AWS

## What is Infrastructure as Code (IaC)?

Infrastructure as Code (IaC) is the practice of managing and provisioning computing infrastructure through machine-readable definition files, rather than manual processes or interactive configuration tools.

Key benefits of IaC:

- **Consistency**: Eliminates manual configuration drift
- **Version Control**: Infrastructure changes can be tracked like code
- **Reproducibility**: Environments can be created identically every time
- **Collaboration**: Teams can work together on infrastructure definitions
- **Speed**: Faster deployment than manual processes

## What is Terraform?

Terraform is an open-source IaC tool created by HashiCorp that enables you to safely and predictably create, change, and improve infrastructure.

Key features:

- **Declarative syntax**: Describe what infrastructure you want, not how to create it
- **Cloud-agnostic**: Works with Azure, AWS, GCP and many other providers
- **State management**: Tracks your real infrastructure and compares to configuration
- **Modularity**: Reusable components through modules
- **Plan/Apply workflow**: Preview changes before executing them

## Terraform for AWS

### Prerequisites

- AWS account with associated credentials
- AWS CLI installed
- Terraform CLI installed

[Click here for terraform installation guide](/install-terraform-awscli.md)

## A Terraform Deployment

In your VM, in your home directory, create a directory for your new deployment `mkdir myProject`, and move into it `cd myProject`.

Create and open a new file named `terraform.tf` and copy the following code:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}
```

Providers manage your resources by calling your cloud provider's APIs. The `required_providers` block lets you set version constraints on the providers your configuration uses.

Below is a Terraform script for deploying two load balanced web servers. It may look overwhelming at first, but we'll break it down below. The script is written in Hashicorp Configuration Language (HCL) which is similar to JSON.

Create a new file called `main.tf` and edit it with `nano`. Copy the below HCL code into the file, save and exit.

```hcl
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

```

## Script Breakdown

<!-- ### Provider Configuration
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.1.0"
}
```
- `required_providers`: Specifies the Azure provider `azurerm` (Azure Resource Manager) and its version.
- `required_version`: Ensures Terraform CLI is at least version 1.1.0. -->

### Variable

```hcl
variable "aws_region" { ... }
variable "vpc_cidr" { ... }
variable "public_subnets" { ... }
variable "instance_type" { ... }
variable "key_name" { ... }
variable "allowed_ssh_cidr" { ... }
```

Defines inputs that make the configuration reusable:

- aws_region: deployment region.
- vpc_cidr: network range for the VPC.
- public_subnets: subnets for EC2 instances and ALB.
- instance_type: e.g., t3.micro.
- key_name: optional SSH key pair.
- allowed_ssh_cidr: controls who can SSH in (if SSH is enabled).

### Networking (VPC, Subnets, IGW, Route Table)

```hcl
resource "aws_vpc" "this" { ... }
resource "aws_internet_gateway" "this" { ... }
data "aws_availability_zones" "available" {}
resource "aws_subnet" "public" { ... }
resource "aws_route_table" "public" { ... }
resource "aws_route_table_association" "public_assoc" { ... }
```

Creates the base network infrastructure:

- VPC: isolated private network.
- Internet Gateway (IGW): gives public internet access.
- Subnets: two public subnets in different AZs for redundancy.
- Route Table: sends all outbound traffic to the IGW.
- Associations: link subnets to the route table so they are public.

### Security Groups

```hcl
resource "aws_security_group" "alb_sg" { ... }
resource "aws_security_group" "instance_sg" { ... }
```

Defines firewall rules:

- ALB SG: allows inbound HTTP (port 80) from anywhere.
- Instance SG: allows HTTP only from the ALB and optional SSH from your IP range.

### Application Load Balancer (ALB)

```hcl
resource "aws_lb" "alb" { ... }
resource "aws_lb_target_group" "web_tg" { ... }
resource "aws_lb_listener" "http" { ... }
```

Creates a highly available ALB:

- aws_lb: the ALB itself, public-facing.
- Target group: holds healthy web servers for load balancing.
- Listener: listens on port 80 and forwards requests to the target group.

### AMI (Amazon Linux 2) and User Data

```hcl
data "aws_ami" "al2" { ... }

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
```

- AMI data source: fetches the latest Amazon Linux 2 image ID automatically.
- User data: installs Nginx and serves a simple HTML page showing the instance hostname.

### Launch Template & Auto Scaling Group

```hcl
resource "aws_launch_template" "web_lt" { ... }
resource "aws_autoscaling_group" "web_asg" { ... }
```

This defines how EC2 instances are created and scaled:

- Launch Template: specifies instance type, AMI, user data, and SGs.
- Auto Scaling Group (ASG): ensures two instances are always running, distributing them across subnets and registering them with the ALB target group.

### Outputs

```hcl
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}
```

After deployment, Terraform prints:

- The ALB’s DNS name (visit this in a browser to test).
- The VPC ID for reference.

## Terraform Commands

**Initialize Terraform**:

```bash
terraform init
```

- Downloads required providers
- Sets up backend (if configured)

**Verify formatting**:

```bash
terraform fmt
```

- Formats Terraform configuration file contents so that it matches the canonical format and style

**Preview changes**:

```bash
terraform plan
```

- Shows what Terraform will do
- No changes are actually made

**Apply changes**:

```bash
terraform apply
```

- Creates/modifies infrastructure
- Requires confirmation unless run with `-auto-approve`

**Destroy resources**:

Explore and verify the new resources through the Management Console if you wish, before running the following command to remove them again.

```bash
terraform destroy
```

- Removes all managed infrastructure
- Useful for cleanup
