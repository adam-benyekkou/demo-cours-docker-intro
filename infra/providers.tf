# Authentication is entirely environment driven so the same configuration works
# from a laptop and from GitHub Actions:
#   ARM_USE_OIDC=true, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# OIDC is enabled by the ARM_USE_OIDC variable, not by a provider argument.
provider "azurerm" {
  features {}
}
