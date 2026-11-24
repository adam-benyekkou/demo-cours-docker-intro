# main.tf — récupère le groupe de ressources créé hors de Terraform.
#
# Point de départ de la stack : toutes les autres ressources s'appuient sur ce
# data source. Le groupe lui-même est créé par infra/bootstrap/bootstrap.sh,
# pas par Terraform.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}
