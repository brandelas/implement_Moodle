# =============================================================================
# versions.tf — Configuração raiz
# Versões mínimas do Terraform e do provider AWS, e configuração do provider.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend local (padrão). O terraform.tfstate contém as credenciais do banco
  # em texto legível e é ignorado pelo .gitignore — nunca commite o state.
  # Um backend S3 com lock foi avaliado e descartado para este desafio
  # (ver docs/architecture-design.md, "Decisões de Design").
}

# Região fixa exigida pelo AWS Academy Learner Lab. As credenciais vêm do
# ambiente (~/.aws/credentials ou variáveis AWS_*), nunca do código.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
