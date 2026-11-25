# =============================================================================
# variables.tf — Configuração raiz
# Variáveis de entrada repassadas aos módulos networking, compute e database.
# Valores obrigatórios (sem padrão) são fornecidos em terraform.tfvars, que é
# ignorado pelo .gitignore. Veja terraform.tfvars.example.
# TODO: Copie terraform.tfvars.example para terraform.tfvars e preencha os valores.
# =============================================================================

# -----------------------------------------------------------------------------
# Gerais
# -----------------------------------------------------------------------------
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Região AWS. O AWS Academy Learner Lab só permite us-east-1."

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "O Learner Lab só permite a região us-east-1."
  }
}

variable "project_name" {
  type        = string
  default     = "moodle"
  description = "Prefixo usado nos nomes e tags de todos os recursos."
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
# sensitive = true evita publicar o IP no comentário do plan na PR.
variable "ssh_allowed_cidr" {
  type        = string
  sensitive   = true
  description = "IP autorizado a acessar a EC2 via SSH, no formato X.X.X.X/32. Nunca use 0.0.0.0/0."
}

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------
variable "ec2_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Tipo da instância EC2 (t3.micro, exigido pelo enunciado da prova)."
}

variable "iam_instance_profile_name" {
  type        = string
  default     = "LabInstanceProfile"
  description = "Instance profile pré-existente do Learner Lab (associado à role LabRole). Nenhum recurso IAM é criado."
}

variable "ec2_public_key" {
  type        = string
  description = "Conteúdo da chave pública OpenSSH (ex.: ssh-ed25519 AAAA...). A chave privada nunca é versionada."
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/brandelas/implement_Moodle.git"
  description = "Repositório público clonado pela EC2 no boot (contém o Dockerfile e o docker-compose.prod.yml)."
}

variable "repo_branch" {
  type        = string
  default     = "main"
  description = "Branch clonada pela EC2. Precisa conter o código desta solução já publicado no GitHub."
}

variable "moodle_admin_user" {
  type        = string
  default     = "admin"
  description = "Usuário administrador do Moodle."
}

variable "moodle_admin_password" {
  type        = string
  sensitive   = true
  description = "Senha do administrador do Moodle (sensível)."
}

variable "moodle_site_name" {
  type        = string
  default     = "Moodle Challenge"
  description = "Nome exibido no site Moodle."
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
variable "db_name" {
  type        = string
  default     = "moodle"
  description = "Nome do banco PostgreSQL criado no RDS."
}

variable "db_username" {
  type        = string
  sensitive   = true
  description = "Usuário master do RDS (sensível)."
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Senha master do RDS (sensível). Mínimo 8 caracteres, sem /, @, \" ou espaço."
}

variable "db_instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "Classe da instância RDS."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Se true, não cria snapshot final ao destruir o RDS (recomendado no Learner Lab)."
}
