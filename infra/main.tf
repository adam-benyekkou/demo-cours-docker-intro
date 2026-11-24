locals {
  prefix = var.prefix

  # Every resource is placed in var.location; the resource group is only a
  # logical container (created by infra/bootstrap/bootstrap.sh).
  location = var.location
  tags     = var.tags
}

# Pre-created by infra/bootstrap/bootstrap.sh.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}
