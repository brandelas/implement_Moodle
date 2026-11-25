# =============================================================================
# outputs.tf — Módulo database
# Exporta os parâmetros de conexão (host, porta, nome, usuário e senha),
# consumidos pelo módulo compute através da configuração raiz.
# TODO: Se migrar para AWS Secrets Manager, remova os outputs de credenciais.
# =============================================================================

output "rds_endpoint" {
  description = "Endpoint da instância RDS no formato hostname:porta."
  value       = aws_db_instance.main.endpoint
}

output "db_host" {
  description = "Hostname do RDS, sem a porta (usado pelo módulo compute)."
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Porta da instância RDS (5432 para PostgreSQL)."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nome do banco de dados criado no RDS."
  value       = aws_db_instance.main.db_name
}

# As credenciais são marcadas como sensitive: não aparecem no plan/apply,
# mas continuam gravadas em texto legível no terraform.tfstate.
output "db_username" {
  description = "Usuário master do RDS (sensível)."
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_password" {
  description = "Senha master do RDS (sensível)."
  value       = var.db_password
  sensitive   = true
}
