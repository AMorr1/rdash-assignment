variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.name_prefix}-sb-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Premium"
  capacity            = 1
  zone_redundant      = true
  tags                = var.tags
}

resource "azurerm_servicebus_topic" "events" {
  name                = "rdash-events"
  namespace_id        = azurerm_servicebus_namespace.this.id
  enable_partitioning = true
}

resource "azurerm_servicebus_subscription" "worker" {
  name                                 = "worker"
  topic_id                             = azurerm_servicebus_topic.events.id
  max_delivery_count                   = 10
  dead_lettering_on_message_expiration = true
}

output "namespace_name" {
  value = azurerm_servicebus_namespace.this.name
}

output "topic_name" {
  value = azurerm_servicebus_topic.events.name
}

