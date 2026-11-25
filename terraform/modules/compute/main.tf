# =============================================================================
# main.tf — Módulo compute
# Recursos AWS: data source da AMI, key pair e instância EC2 com user_data.
# TODO: Após o apply, acompanhe o boot com: sudo tail -f /var/log/user-data-moodle.log
# =============================================================================

# -----------------------------------------------------------------------------
# Provider — hashicorp/aws ~> 5.0
# Declarado no módulo para permitir validação isolada (terraform init +
# terraform validate neste diretório) sem depender da configuração raiz.
# -----------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data source — AMI do Amazon Linux 2023 (D-02)
# Busca a versão mais recente em vez de fixar um ID, pois IDs de AMI são
# específicos por região e mudam com as atualizações. O filtro "al2023-ami-2023"
# exclui a variante "minimal".
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Par de chaves SSH (D-04)
# Apenas a chave pública é declarada aqui; a chave privada fica exclusivamente
# no sistema local. Chave pública não é dado sensível (sem sensitive = true).
# -----------------------------------------------------------------------------
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.ec2_public_key

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Instância EC2 do Moodle
# - iam_instance_profile: perfil pré-existente "LabInstanceProfile" do Learner
#   Lab (role LabRole). Passado por nome; nenhum recurso IAM é criado (D-03 rev.).
# - metadata_options: IMDSv2 obrigatório (D-05).
# - user_data: templatefile() com credenciais em Base64 (D-07). Base64 não é
#   criptografia; os valores também ficam no state e no IMDS.
# - user_data_replace_on_change: alterar o script recria a instância, pois o
#   cloud-init só executa o user_data no primeiro boot.
# -----------------------------------------------------------------------------
resource "aws_instance" "main" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_app_id]
  key_name               = aws_key_pair.main.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    db_password_b64       = base64encode(var.db_password)
    db_username_b64       = base64encode(var.db_username)
    moodle_admin_pass_b64 = base64encode(var.moodle_admin_password)
    rds_endpoint          = var.rds_endpoint
    db_name               = var.db_name
    moodle_admin_user     = var.moodle_admin_user
    moodle_site_name      = var.moodle_site_name
    repo_url              = var.repo_url
    repo_branch           = var.repo_branch
  })
  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}
