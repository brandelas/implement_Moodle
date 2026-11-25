# =============================================================================
# main.tf — Módulo database
# Provisiona o DB Subnet Group e a instância RDS PostgreSQL para o Moodle.
#
# TODO: Confirmar no terraform plan que engine_version = "15" é aceito no
#       Learner Lab (ver PC-01 em .kiro/specs/database/design.md).
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
# DB Subnet Group — agrupa as subnets privadas em 2 AZs para o RDS.
# A validação de exatamente 2 subnets é feita em variables.tf.
# A garantia de AZs distintas é responsabilidade do módulo networking.
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.project_name}-db-subnet-group"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Instância RDS PostgreSQL 15.
# - publicly_accessible = false: sem endpoint público; acesso somente pela VPC.
# - vpc_security_group_ids: somente o sg-db do módulo networking (TCP 5432
#   restrito ao sg-app). Nenhum Security Group é criado neste módulo.
# - skip_final_snapshot: controlado por variável (padrão true para o Learn Lab).
# - engine_version = "15": versão major; confirmar disponibilidade no Learn Lab.
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_db_id]

  publicly_accessible       = false
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-db-final"

  tags = {
    Name    = "${var.project_name}-db"
    Project = var.project_name
  }
}
