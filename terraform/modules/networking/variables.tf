# =============================================================================
# variables.tf — Módulo networking
# Declara todas as variáveis de entrada do módulo com validações de cardinalidade
# e formato.
# TODO: Ajuste os valores padrão conforme a topologia do seu projeto, se necessário.
# =============================================================================

# -----------------------------------------------------------------------------
# Nome do projeto — usado como prefixo em nomes e tags de todos os recursos.
# -----------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Prefixo usado nos nomes e tags de todos os recursos do módulo networking."
}

# -----------------------------------------------------------------------------
# CIDR da VPC principal.
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block da VPC principal."
}

# -----------------------------------------------------------------------------
# CIDRs das subnets públicas — exatamente 2 elementos.
# -----------------------------------------------------------------------------
variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Lista de CIDRs das subnets públicas. Deve conter exatamente 2 elementos, um por AZ."

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs deve conter exatamente 2 CIDRs."
  }
}

# -----------------------------------------------------------------------------
# CIDRs das subnets privadas — exatamente 2 elementos.
# -----------------------------------------------------------------------------
variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Lista de CIDRs das subnets privadas. Deve conter exatamente 2 elementos, um por AZ."

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs deve conter exatamente 2 CIDRs."
  }
}

# -----------------------------------------------------------------------------
# Availability Zones — exatamente 2, obrigatoriamente distintas.
# A condição condicional evita acesso a índices inexistentes quando a lista
# tem menos de 2 elementos.
# -----------------------------------------------------------------------------
variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "Lista de AZs onde as subnets serão criadas. Deve conter exatamente 2 AZs distintas."

  validation {
    condition = length(var.availability_zones) == 2 ? (
      var.availability_zones[0] != var.availability_zones[1]
    ) : false

    error_message = "Informe exatamente 2 AZs distintas."
  }
}

# -----------------------------------------------------------------------------
# CIDR autorizado para SSH na EC2 — obrigatório, sem valor padrão.
# Deve ser um IPv4 individual com máscara /32 (ex.: 203.0.113.10/32).
# Valores abertos como 0.0.0.0/0 expõem a porta 22 à internet.
# -----------------------------------------------------------------------------
variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR IPv4 autorizado para acesso SSH à EC2. Informe um único IP no formato X.X.X.X/32 (ex.: 203.0.113.10/32). AVISO: valores abertos como 0.0.0.0/0 expõem a porta SSH a qualquer origem na internet."

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_allowed_cidr))
    error_message = "Informe um único IPv4 autorizado para SSH no formato X.X.X.X/32."
  }
}
