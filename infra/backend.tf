# backend.tf — déclare le backend azurerm du state, en configuration partielle.
#
# Le nom du compte de stockage est généré par infra/bootstrap/bootstrap.sh : la CI
# fournit le reste au moment de l'init. Aucun identifiant n'est stocké ici.
#
# Configuration partielle volontaire : le nom du compte de stockage est généré par
# infra/bootstrap/bootstrap.sh, donc la CI fournit les paramètres restants à l'init :
#
#   terraform init \
#     -backend-config="resource_group_name=${TF_STATE_RESOURCE_GROUP}" \
#     -backend-config="storage_account_name=${TF_STATE_STORAGE_ACCOUNT}" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=demo-cours-docker-intro.tfstate" \
#     -backend-config="use_oidc=true" \
#     -backend-config="use_azuread_auth=true"
terraform {
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "demo-cours-docker-intro.tfstate"
    use_azuread_auth = true
  }
}
