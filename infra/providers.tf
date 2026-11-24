# providers.tf — déclare le provider Azure et la manière dont il s'authentifie.
#
# L'authentification vient entièrement de l'environnement, pour que la même
# configuration serve depuis un poste et depuis GitHub Actions :
#   ARM_USE_OIDC=true, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# OIDC s'active par la variable ARM_USE_OIDC, pas par un argument du provider.
provider "azurerm" {
  features {}
}
