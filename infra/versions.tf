# versions.tf — fixe la version de Terraform et du provider azurerm de la stack.
#
# À lire avant toute mise à jour de provider : c'est le seul endroit où les
# contraintes de version sont déclarées. Ne décrit aucune ressource.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}
