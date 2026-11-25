# =============================================================================
# variables.tf — Módulo compute
# Declara todas as variáveis de entrada do módulo.
# TODO: Preencha os valores obrigatórios (sem padrão) no terraform.tfvars da raiz.
# =============================================================================

# -----------------------------------------------------------------------------
# Identificação do projeto — prefixo para nomes e tags de todos os recursos.
# -----------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Prefixo usado nos nomes e tags de todos os recursos do módulo compute."
}

# -----------------------------------------------------------------------------
# Tipo da instância EC2.
# O enunciado da prova (requisito mais específico) exige t3.micro. O 1 GB de
# RAM é complementado por swap de 2 GB criado no user_data.sh.
# -----------------------------------------------------------------------------
variable "ec2_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Tipo da instância EC2. Padrão: t3.micro (exigido pelo enunciado da prova)."
}

# -----------------------------------------------------------------------------
# Instance profile pré-existente do Learner Lab (role LabRole).
# Passado por nome no aws_instance; nenhum recurso IAM é criado.
# -----------------------------------------------------------------------------
variable "iam_instance_profile_name" {
  type        = string
  default     = "LabInstanceProfile"
  description = "Nome do instance profile pré-existente no Learner Lab (LabInstanceProfile, associado à role LabRole)."
}

# -----------------------------------------------------------------------------
# Disco raiz da EC2 (gp3, criptografado).
# -----------------------------------------------------------------------------
variable "root_volume_size" {
  type        = number
  default     = 16
  description = "Tamanho do disco raiz em GB (padrão 16 GB: sistema, imagem Docker do Moodle e swap de 2 GB)."

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size deve ser de no mínimo 8 GB (tamanho do snapshot da AMI Amazon Linux 2023)."
  }
}

# -----------------------------------------------------------------------------
# Repositório clonado pela EC2 no boot (Dockerfile + docker-compose.prod.yml).
# -----------------------------------------------------------------------------
variable "repo_url" {
  type        = string
  description = "URL HTTPS do repositório público clonado pela EC2 no boot."
}

variable "repo_branch" {
  type        = string
  default     = "main"
  description = "Branch clonada pela EC2. Deve conter o docker-compose.prod.yml já publicado."
}

# -----------------------------------------------------------------------------
# Chave pública SSH para o aws_key_pair.
# Chave pública não é dado sensível — não usa sensitive = true.
# A chave privada nunca deve ser declarada aqui nem versionada no repositório.
# -----------------------------------------------------------------------------
variable "ec2_public_key" {
  type        = string
  description = "Conteúdo da chave pública OpenSSH para o aws_key_pair (ex.: ssh-rsa AAAA...). Apenas a chave pública é declarada aqui; a chave privada fica exclusivamente no sistema local."
}

# -----------------------------------------------------------------------------
# IDs de rede — recebidos do módulo networking via configuração raiz.
# -----------------------------------------------------------------------------
variable "subnet_id" {
  type        = string
  description = "ID da subnet pública onde a instância EC2 será criada. Corresponde a module.networking.public_subnet_ids[0] na raiz."
}

variable "sg_app_id" {
  type        = string
  description = "ID do Security Group da EC2 (sg-app). Corresponde a module.networking.sg_app_id na raiz."
}

# -----------------------------------------------------------------------------
# Endpoint do RDS — recebido do módulo database via configuração raiz.
# Deve conter somente o hostname, sem a porta (output db_host do módulo database).
# -----------------------------------------------------------------------------
variable "rds_endpoint" {
  type        = string
  description = "Hostname do RDS PostgreSQL (sem a porta). Corresponde a module.database.db_host na raiz."
}

# -----------------------------------------------------------------------------
# Configurações do banco de dados.
# db_username e db_password são sensíveis — não aparecem no plano em texto claro.
# NOTA: sensitive = true não impede o registro no terraform.tfstate.
# -----------------------------------------------------------------------------
variable "db_name" {
  type        = string
  default     = "moodle"
  description = "Nome do banco de dados PostgreSQL no RDS."
}

variable "db_username" {
  type        = string
  sensitive   = true
  description = "Usuário master do banco de dados RDS (sensível — forneça via terraform.tfvars)."
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Senha master do banco de dados RDS (sensível — forneça via terraform.tfvars). Não deve conter quebras de linha."
}

# -----------------------------------------------------------------------------
# Configurações do administrador Moodle.
# moodle_admin_password é sensível.
# -----------------------------------------------------------------------------
variable "moodle_admin_user" {
  type        = string
  default     = "admin"
  description = "Nome de usuário do administrador do Moodle."
}

variable "moodle_admin_password" {
  type        = string
  sensitive   = true
  description = "Senha do administrador do Moodle (sensível — forneça via terraform.tfvars). Não deve conter quebras de linha."
}

variable "moodle_site_name" {
  type        = string
  default     = "Moodle Challenge"
  description = "Nome exibido no site Moodle."
}
