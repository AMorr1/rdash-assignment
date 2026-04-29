locals {
  common_tags = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      project     = "rdash-assignment"
    },
    var.tags
  )

  cidrs = {
    public_a  = "10.20.0.0/22"
    public_b  = "10.20.4.0/22"
    private_a = "10.20.8.0/20"
    private_b = "10.20.24.0/20"
    database  = "10.20.40.0/24"
    cache     = "10.20.41.0/24"
    pods      = "10.40.0.0/16"
    services  = "10.41.0.0/16"
  }

  names = {
    resource_group = "${var.name_prefix}-${var.environment}-rg"
    aks            = "${var.name_prefix}-${var.environment}-aks"
    vnet           = "${var.name_prefix}-${var.environment}-vnet"
  }
}

