resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source              = "./modules/network"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}-${var.environment}"
  address_space       = ["10.20.0.0/16"]
  subnet_cidrs        = local.cidrs
  tags                = local.common_tags
}

module "storage" {
  source              = "./modules/storage"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}${var.environment}"
  tenant_id           = var.tenant_id
  tags                = local.common_tags
}

module "keyvault" {
  source              = "./modules/keyvault"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}-${var.environment}"
  tenant_id           = var.tenant_id
  tags                = local.common_tags
}

module "servicebus" {
  source              = "./modules/servicebus"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}-${var.environment}"
  tags                = local.common_tags
}

module "redis" {
  source              = "./modules/redis"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}-${var.environment}"
  subnet_id           = module.network.cache_subnet_id
  tags                = local.common_tags
}

module "postgres_core" {
  source                 = "./modules/postgres"
  location               = var.location
  resource_group_name    = azurerm_resource_group.this.name
  name_prefix            = "${var.name_prefix}-${var.environment}-core"
  delegated_subnet_id    = module.network.database_subnet_id
  private_dns_zone_id    = module.network.postgres_private_dns_zone_id
  admin_login            = var.postgres_admin_login
  admin_password         = var.postgres_admin_password
  database_name          = "coredb"
  create_replica         = true
  high_availability_mode = "ZoneRedundant"
  tags                   = local.common_tags
}

module "postgres_registry" {
  source                 = "./modules/postgres"
  location               = var.location
  resource_group_name    = azurerm_resource_group.this.name
  name_prefix            = "${var.name_prefix}-${var.environment}-registry"
  delegated_subnet_id    = module.network.database_subnet_id
  private_dns_zone_id    = module.network.postgres_private_dns_zone_id
  admin_login            = var.postgres_admin_login
  admin_password         = var.postgres_admin_password
  database_name          = "registrydb"
  create_replica         = false
  high_availability_mode = "ZoneRedundant"
  tags                   = local.common_tags
}

module "aks" {
  source                 = "./modules/aks"
  location               = var.location
  resource_group_name    = azurerm_resource_group.this.name
  name                   = local.names.aks
  kubernetes_version     = var.kubernetes_version
  private_cluster        = false
  authorized_ip_ranges   = var.authorized_ip_ranges
  subnet_id              = module.network.private_subnet_ids[0]
  pod_subnet_id          = module.network.private_subnet_ids[1]
  workload_identity_name = module.storage.workload_identity_name
  tags                   = local.common_tags
}

module "frontdoor" {
  count               = var.enable_frontdoor ? 1 : 0
  source              = "./modules/frontdoor"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name_prefix         = "${var.name_prefix}-${var.environment}"
  dns_zone_name       = var.dns_zone_name
  endpoint_host       = var.domain_name
  tags                = local.common_tags
}

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
  }
}

resource "kubernetes_namespace" "rdash" {
  metadata {
    name = "rdash"
  }
}

resource "helm_release" "platform_addons" {
  name             = "platform-addons"
  namespace        = kubernetes_namespace.platform.metadata[0].name
  chart            = "${path.module}/../helm/charts/platform-addons"
  create_namespace = false

  values = [
    yamlencode({
      global = {
        domain_name       = var.domain_name
        letsencrypt_email = var.letsencrypt_email
        slack_webhook_url = var.slack_webhook_url
        grafana_password  = var.grafana_admin_password
        storage_account   = module.storage.storage_account_name
        storage_container = module.storage.container_name
        tenant_id         = var.tenant_id
        keyvault_name     = module.keyvault.name
      }
    })
  ]
}
