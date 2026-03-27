terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "main" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sre-assessment-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "sre-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "sre-private-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "sre-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "sre-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group — VM1 (gateway / public)
resource "aws_security_group" "vm1" {
  name        = "sre-vm1-sg"
  description = "Gateway VM: SSH from my IP, HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  # SSH from your IP only
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # HTTP from anywhere
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS from anywhere
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sre-vm1-sg"
  }
}

# Security Group — VM2 (app server / private)
resource "aws_security_group" "vm2" {
  name        = "sre-vm2-sg"
  description = "App server VM: all traffic from VM1 SG only, deny everything else"
  vpc_id      = aws_vpc.main.id

  # All traffic from VM1's security group (within private subnet)
  ingress {
    description     = "All traffic from VM1"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.vm1.id]
  }

  # All outbound allowed (so VM2 can respond and reach internet via VM1 if needed)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sre-vm2-sg"
  }
}

# AMI — Latest Ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VM1 — Gateway (public subnet, public IP)
resource "aws_instance" "vm1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.vm1.id]

  tags = {
    Name = "sre-vm1-gateway"
  }
}

# VM2 — App Server (private subnet, no public IP)
resource "aws_instance" "vm2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.vm2.id]

  tags = {
    Name = "sre-vm2-appserver"
  }
}
