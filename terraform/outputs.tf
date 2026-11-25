# =============================================================================
# outputs.tf — Configuração raiz
# Outputs exigidos pela rubrica: ec2_public_dns, rds_endpoint e vpc_id.
# TODO: Após o apply, use `terraform output moodle_url` para abrir o Moodle.
# =============================================================================

output "vpc_id" {
  description = "ID da VPC criada."
  value       = module.networking.vpc_id
}

output "ec2_public_dns" {
  description = "DNS público da EC2 que hospeda o Moodle."
  value       = module.compute.public_dns
}

output "ec2_public_ip" {
  description = "IP público da EC2."
  value       = module.compute.public_ip
}

output "rds_endpoint" {
  description = "Endpoint do RDS no formato host:porta (acessível somente de dentro da VPC)."
  value       = module.database.rds_endpoint
}

output "moodle_url" {
  description = "URL pública do Moodle."
  value       = "http://${module.compute.public_dns}"
}
