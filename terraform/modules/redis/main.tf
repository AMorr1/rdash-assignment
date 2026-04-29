variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "subnet_id" { type = string }
variable "tags" { type = map(string) }

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_redis_cache" "this" {
  name                          = "${var.name_prefix}-redis-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  capacity                      = 2
  family                        = "P"
  sku_name                      = "Premium"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  shard_count                   = 2
  subnet_id                     = var.subnet_id
  replicas_per_primary          = 1
  tags                          = var.tags
}

output "hostname" {
  value = azurerm_redis_cache.this.hostname
}

