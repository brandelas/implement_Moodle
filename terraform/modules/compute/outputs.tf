# =============================================================================
# outputs.tf — Módulo compute
# Exporta os identificadores públicos da EC2 (exigidos pelo enunciado da prova:
# public_ip e public_dns).
# TODO: Se adicionar um Load Balancer no futuro, exporte o DNS do ALB aqui.
# =============================================================================

output "public_ip" {
  description = "IP público da instância EC2."
  value       = aws_instance.main.public_ip
}

output "public_dns" {
  description = "DNS público da instância EC2 (usado no health check e no entrega.md)."
  value       = aws_instance.main.public_dns
}

output "instance_id" {
  description = "ID da instância EC2."
  value       = aws_instance.main.id
}
