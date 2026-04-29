variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "delegated_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "admin_login" { type = string }
variable "admin_password" { type = string }
variable "database_name" { type = string }
variable "create_replica" { type = bool }
variable "high_availability_mode" { type = string }
variable "tags" { type = map(string) }

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_postgresql_flexible_server" "primary" {
  name                   = "${var.name_prefix}-pg-${random_string.suffix.result}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  delegated_subnet_id    = var.delegated_subnet_id
  private_dns_zone_id    = var.private_dns_zone_id
  administrator_login    = var.admin_login
  administrator_password = var.admin_password
  zone                   = "1"
  storage_mb             = 131072
  sku_name               = "GP_Standard_D4ds_v5"
  backup_retention_days  = 7
  tags                   = var.tags

  high_availability {
    mode = var.high_availability_mode
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.primary.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server" "replica" {
  count               = var.create_replica ? 1 : 0
  name                = "${var.name_prefix}-replica-${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  create_mode         = "Replica"
  source_server_id    = azurerm_postgresql_flexible_server.primary.id
  zone                = "2"
  tags                = var.tags
}

output "primary_fqdn" {
  value = azurerm_postgresql_flexible_server.primary.fqdn
}

output "replica_fqdn" {
  value = var.create_replica ? azurerm_postgresql_flexible_server.replica[0].fqdn : null
}

