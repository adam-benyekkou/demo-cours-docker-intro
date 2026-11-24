# Pre-created by infra/bootstrap/bootstrap.sh.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}
