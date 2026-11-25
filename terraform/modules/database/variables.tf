# =============================================================================
# variables.tf — Módulo database
# Declara todas as variáveis de entrada do módulo.
# TODO: Preencha os valores obrigatórios (sem padrão) no terraform.tfvars da raiz.
# =============================================================================

# -----------------------------------------------------------------------------
# Identificação do projeto — prefixo para nomes e tags de todos os recursos.
# -----------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Prefixo usado nos nomes e tags de todos os recursos do módulo database."
}

# -----------------------------------------------------------------------------
# IDs das subnets privadas — recebidos do módulo networking via configuração raiz.
# Devem ser exatamente 2 subnets, em AZs distintas, para satisfazer o requisito
# mínimo do aws_db_subnet_group.
# A garantia de AZs distintas é responsabilidade do módulo networking.
# -----------------------------------------------------------------------------
variable "private_subnet_ids" {
  type        = list(string)
  description = "Lista com exatamente 2 IDs de subnets privadas (em AZs distintas) para o DB Subnet Group. Corresponde a module.networking.private_subnet_ids na raiz."

  validation {
    condition     = length(var.private_subnet_ids) == 2
    error_message = "private_subnet_ids deve conter exatamente 2 IDs de subnets privadas."
  }
}

# -----------------------------------------------------------------------------
# ID do Security Group do banco — recebido do módulo networking.
# O SG já foi criado com a regra TCP 5432 restrita ao sg-app.
# -----------------------------------------------------------------------------
variable "sg_db_id" {
  type        = string
  description = "ID do Security Group do RDS (sg-db), criado pelo módulo networking com regra TCP 5432 exclusivamente a partir do sg-app. Corresponde a module.networking.sg_db_id na raiz."
}

# -----------------------------------------------------------------------------
# Nome do banco de dados a criar no RDS.
# -----------------------------------------------------------------------------
variable "db_name" {
  type        = string
  default     = "moodle"
  description = "Nome do banco de dados PostgreSQL a criar na instância RDS."
}

# -----------------------------------------------------------------------------
# Credenciais do banco — sensíveis.
# NOTA: sensitive = true evita que os valores apareçam no output do terraform plan
# e terraform apply, mas NÃO impede que sejam gravados em texto legível no
# terraform.tfstate. O arquivo de state nunca deve ser commitado no repositório
# (.gitignore já cobre terraform.tfstate e terraform.tfstate.backup).
# -----------------------------------------------------------------------------
variable "db_username" {
  type        = string
  sensitive   = true
  description = "Usuário master da instância RDS (sensível — forneça via terraform.tfvars). AVISO: sensitive = true não impede o registro em texto legível no terraform.tfstate; nunca commite o state."

  # Regras do RDS PostgreSQL: começa com letra, só letras/números/_, até 63 caracteres.
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_username))
    error_message = "db_username deve começar com letra e conter apenas letras, números ou _ (até 63 caracteres)."
  }
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Senha master da instância RDS (sensível — forneça via terraform.tfvars). AVISO: sensitive = true não impede o registro em texto legível no terraform.tfstate; nunca commite o state. Não deve conter quebras de linha."

  # Regras do RDS: 8 a 128 caracteres; não aceita /, @, " ou espaço.
  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128 && !can(regex("[/@\" ]", var.db_password))
    error_message = "db_password deve ter de 8 a 128 caracteres e não pode conter /, @, \" ou espaço."
  }
}

# -----------------------------------------------------------------------------
# Classe da instância RDS.
# -----------------------------------------------------------------------------
variable "db_instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "Classe da instância RDS. Padrão: db.t3.micro (exigido pela rubrica de avaliação — docs/evaluation-rubric.md p. 86)."
}

# -----------------------------------------------------------------------------
# Comportamento de snapshot final ao destruir o RDS.
# Padrão true: evita erros em reexecuções do terraform destroy no Learn Lab,
# onde snapshots com nomes repetidos causam falha. Sobrescreva para false no
# terraform.tfvars se quiser preservar um snapshot de demonstração.
# -----------------------------------------------------------------------------
variable "skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Se true, não cria snapshot final ao destruir o RDS (padrão recomendado no Learn Lab). Defina false no terraform.tfvars para preservar um snapshot de demonstração."
}
