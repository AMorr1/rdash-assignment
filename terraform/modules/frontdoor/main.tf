variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "dns_zone_name" { type = string }
variable "endpoint_host" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name_prefix}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = replace("${var.name_prefix}-ep", "-", "")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  enabled                  = true
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "${var.name_prefix}-og"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {}
  health_probe {
    interval_in_seconds = 120
    path                = "/healthz"
    protocol            = "Https"
    request_type        = "GET"
  }
}

resource "azurerm_cdn_frontdoor_origin" "ingress" {
  name                           = "aksingress"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                        = true
  certificate_name_check_enabled = false
  host_name                      = var.endpoint_host
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.endpoint_host
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "${var.name_prefix}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.ingress.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = true
}

output "endpoint" {
  value = azurerm_cdn_frontdoor_endpoint.this.host_name
}
