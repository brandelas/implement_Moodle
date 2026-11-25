# =============================================================================
# outputs.tf — Módulo networking
# Exporta os IDs dos recursos criados para consumo pelos módulos compute e database.
# TODO: Exportar novos IDs aqui caso outros módulos passem a depender da rede.
# =============================================================================

output "vpc_id" {
  description = "ID da VPC principal"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Lista de IDs das subnets publicas"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Lista de IDs das subnets privadas (usada pelo modulo database)"
  value       = [for s in aws_subnet.private : s.id]
}

output "sg_app_id" {
  description = "ID do Security Group da EC2 (sg-app)"
  value       = aws_security_group.sg_app.id
}

output "sg_db_id" {
  description = "ID do Security Group do RDS (sg-db)"
  value       = aws_security_group.sg_db.id
}
