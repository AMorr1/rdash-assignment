variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID."
  type        = string
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Global prefix for resources."
  type        = string
  default     = "rdash"
}

variable "kubernetes_version" {
  description = "AKS version."
  type        = string
  default     = "1.31"
}

variable "authorized_ip_ranges" {
  description = "Optional list of IP ranges for public AKS API access."
  type        = list(string)
  default     = []
}

variable "postgres_admin_login" {
  description = "Flexible Server admin username."
  type        = string
  default     = "rdashadmin"
}

variable "postgres_admin_password" {
  description = "Flexible Server admin password."
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password for bootstrap."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook for Alertmanager."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Base public domain for ingress."
  type        = string
}

variable "dns_zone_name" {
  description = "Azure DNS zone used for public endpoints."
  type        = string
}

variable "letsencrypt_email" {
  description = "Email used by cert-manager ACME issuer."
  type        = string
}

variable "enable_frontdoor" {
  description = "Whether to provision Azure Front Door/CDN."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}
