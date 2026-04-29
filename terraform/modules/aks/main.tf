variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name" { type = string }
variable "kubernetes_version" { type = string }
variable "private_cluster" { type = bool }
variable "authorized_ip_ranges" { type = list(string) }
variable "subnet_id" { type = string }
variable "pod_subnet_id" { type = string }
variable "workload_identity_name" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "${var.name}-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_kubernetes_cluster" "this" {
  name                             = var.name
  location                         = var.location
  resource_group_name              = var.resource_group_name
  dns_prefix                       = var.name
  kubernetes_version               = var.kubernetes_version
  automatic_upgrade_channel        = "stable"
  sku_tier                         = "Standard"
  private_cluster_enabled          = var.private_cluster
  azure_policy_enabled             = true
  oidc_issuer_enabled              = true
  workload_identity_enabled        = true
  image_cleaner_enabled            = true
  http_application_routing_enabled = false
  tags                             = var.tags

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D4ds_v5"
    zones                        = ["1", "2", "3"]
    vnet_subnet_id               = var.subnet_id
    pod_subnet_id                = var.pod_subnet_id
    temporary_name_for_rotation  = "systemtmp"
    type                         = "VirtualMachineScaleSets"
    auto_scaling_enabled         = true
    min_count                    = 2
    max_count                    = 4
    max_pods                     = 50
    only_critical_addons_enabled = true
    node_labels = {
      pool = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "10.41.0.10"
    service_cidr      = "10.41.0.0/16"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "app" {
  name                  = "app"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D8ds_v5"
  zones                 = ["1", "2", "3"]
  vnet_subnet_id        = var.subnet_id
  pod_subnet_id         = var.pod_subnet_id
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = 3
  max_count             = 10
  max_pods              = 40
  node_labels = {
    pool = "app"
  }
  node_taints = ["workload=app:NoSchedule"]
  tags        = var.tags
}

output "name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "host" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].host
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
  sensitive = true
}

output "client_key" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}
