output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  value = module.aks.name
}

output "blob_container" {
  value = module.storage.container_name
}

output "servicebus_topic" {
  value = module.servicebus.topic_name
}

output "keyvault_name" {
  value = module.keyvault.name
}

output "frontdoor_endpoint" {
  value = var.enable_frontdoor ? module.frontdoor[0].endpoint : null
}

output "core_postgres_fqdn" {
  value = module.postgres_core.primary_fqdn
}

output "registry_postgres_fqdn" {
  value = module.postgres_registry.primary_fqdn
}
