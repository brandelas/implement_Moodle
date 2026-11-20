# =============================================================================
# main.tf — Módulo networking
# Recursos AWS: VPC, subnets, IGW, route tables e security groups.
# TODO: Implementar subnets, IGW, route tables e security groups (TASK-04 a TASK-09).
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC principal — CIDR 10.0.0.0/16 com DNS habilitado.
# O DNS hostnames é necessário para que a EC2 receba um DNS público resolvível.
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Subnets públicas — 2 subnets em AZs distintas com IP público automático.
# Cada subnet é criada via count indexado sobre as listas de CIDRs e AZs.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-${count.index + 1}"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Subnets privadas — 2 subnets em AZs distintas para isolamento do RDS.
# Sem IP público automático: o RDS não deve ser alcançável diretamente pela internet.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name    = "${var.project_name}-private-${count.index + 1}"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway — associado à VPC para permitir tráfego de entrada e saída
# das subnets públicas.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Route Table pública — rota padrão 0.0.0.0/0 direcionada ao Internet Gateway.
# Associada a ambas as subnets públicas; as subnets privadas não recebem
# associação com esta Route Table.
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-rt-public"
    Project = var.project_name
  }
}

# aws_route_table_association não suporta a propriedade tags (ver D-04).
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Security Group sg-app — para a instância EC2 (Moodle).
# Ingresso: HTTP (80) aberto para a internet; SSH (22) restrito ao CIDR do aluno.
# Egresso: irrestrito (necessário para pull de imagens Docker, atualizações e
# conexão ao RDS na subnet privada).
# -----------------------------------------------------------------------------
resource "aws_security_group" "sg_app" {
  name        = "${var.project_name}-sg-app"
  description = "Security Group da EC2 — Moodle"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico para o Moodle"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH administrativo (restrito por ssh_allowed_cidr)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "Saida irrestrita"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg-app"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Security Group sg-db — para o RDS (PostgreSQL).
# Ingresso: TCP 5432 exclusivamente a partir do sg-app (referenciado via
# security_groups, nunca via cidr_blocks). O RDS fica acessível apenas pela
# aplicação Moodle na EC2, respeitando o princípio do menor privilégio.
# -----------------------------------------------------------------------------
resource "aws_security_group" "sg_db" {
  name        = "${var.project_name}-sg-db"
  description = "Security Group do RDS — acesso somente a partir do sg-app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL somente a partir do SG da EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_app.id]
  }

  tags = {
    Name    = "${var.project_name}-sg-db"
    Project = var.project_name
  }
}
