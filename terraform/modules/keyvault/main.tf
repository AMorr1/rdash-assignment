variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tenant_id" { type = string }
variable "tags" { type = map(string) }

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = substr(replace("${var.name_prefix}-kv-${random_string.suffix.result}", "-", ""), 0, 24)
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  public_network_access_enabled = true
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  tags                          = var.tags
}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover",
  ]
}

output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

