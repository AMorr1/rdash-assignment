variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "address_space" { type = list(string) }
variable "subnet_cidrs" { type = map(string) }
variable "tags" { type = map(string) }

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_public_ip" "nat" {
  name                = "${var.name_prefix}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.name_prefix}-nat"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_network_security_group" "public" {
  name                = "${var.name_prefix}-public-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "private" {
  name                = "${var.name_prefix}-private-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "database" {
  name                = "${var.name_prefix}-database-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "cache" {
  name                = "${var.name_prefix}-cache-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "database_deny_public" {
  name                        = "deny-public-to-database"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.subnet_cidrs.public_a
  destination_address_prefix  = var.subnet_cidrs.database
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.database.name
}

resource "azurerm_network_security_rule" "cache_deny_public" {
  name                        = "deny-public-to-cache"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.subnet_cidrs.public_b
  destination_address_prefix  = var.subnet_cidrs.cache
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.cache.name
}

resource "azurerm_route_table" "private" {
  name                = "${var.name_prefix}-private-rt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name           = "internet-via-nat"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_network_watcher" "this" {
  name                = "${var.name_prefix}-nw"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_storage_account" "flow_logs" {
  name                            = substr(replace("${var.name_prefix}flowlogs", "-", ""), 0, 24)
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name_prefix}-postgres-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

locals {
  subnet_defs = {
    public-a  = { cidr = var.subnet_cidrs.public_a, nsg = azurerm_network_security_group.public.id, nat = false, delegation = null }
    public-b  = { cidr = var.subnet_cidrs.public_b, nsg = azurerm_network_security_group.public.id, nat = false, delegation = null }
    private-a = { cidr = var.subnet_cidrs.private_a, nsg = azurerm_network_security_group.private.id, nat = true, delegation = "Microsoft.ContainerService/managedClusters" }
    private-b = { cidr = var.subnet_cidrs.private_b, nsg = azurerm_network_security_group.private.id, nat = true, delegation = "Microsoft.ContainerService/managedClusters" }
    database  = { cidr = var.subnet_cidrs.database, nsg = azurerm_network_security_group.database.id, nat = false, delegation = "Microsoft.DBforPostgreSQL/flexibleServers" }
    cache     = { cidr = var.subnet_cidrs.cache, nsg = azurerm_network_security_group.cache.id, nat = false, delegation = null }
  }
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnet_defs
  name                 = "${var.name_prefix}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = "delegation"
      service_delegation {
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        name    = delegation.value
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.subnet_defs
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = each.value.nsg
}

resource "azurerm_subnet_route_table_association" "private" {
  for_each       = { for k, v in local.subnet_defs : k => v if v.nat }
  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.private.id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  for_each       = { for k, v in local.subnet_defs : k => v if v.nat }
  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_network_watcher_flow_log" "nsg" {
  for_each = {
    public   = azurerm_network_security_group.public.id
    private  = azurerm_network_security_group.private.id
    database = azurerm_network_security_group.database.id
    cache    = azurerm_network_security_group.cache.id
  }
  name                      = "${var.name_prefix}-${each.key}-flowlog"
  network_watcher_name      = azurerm_network_watcher.this.name
  resource_group_name       = var.resource_group_name
  network_security_group_id = each.value
  storage_account_id        = azurerm_storage_account.flow_logs.id
  enabled                   = true
  version                   = 2

  retention_policy {
    days    = 7
    enabled = true
  }

  traffic_analytics {
    enabled = false
  }
}

output "private_subnet_ids" {
  value = [
    azurerm_subnet.this["private-a"].id,
    azurerm_subnet.this["private-b"].id,
  ]
}

output "database_subnet_id" {
  value = azurerm_subnet.this["database"].id
}

output "cache_subnet_id" {
  value = azurerm_subnet.this["cache"].id
}

output "postgres_private_dns_zone_id" {
  value = azurerm_private_dns_zone.postgres.id
}
