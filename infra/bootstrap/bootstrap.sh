#!/usr/bin/env bash
# bootstrap.sh — amorçage Azure unique (rejouable) de la stack de démo.
#
# À lancer une seule fois, avant le premier terraform init : crée le stockage du
# state distant et le groupe de ressources que Terraform ne peut pas créer
# lui-même :
#   - rg-tfstate + compte de stockage + conteneur tfstate (state distant)
#   - rg-demo-docker, le groupe de ressources qui porte toute la stack
#
# Aucune identité Azure et aucun secret ne sont créés : la CI tourne sur un
# runner auto-hébergé installé sur la VM et n'appelle jamais l'API Azure.
# Terraform est appliqué à la main, avec votre `az login`.
#
# Prérequis : az (connecté), openssl.

set -euo pipefail

# --- variables du script ----------------------------------------------------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
LOCATION="${LOCATION:-francecentral}"

TF_STATE_RG="rg-tfstate"
APP_RG="rg-demo-docker"
STATE_CONTAINER="tfstate"

# --- fonctions utilitaires --------------------------------------------------
log() { printf '==> %s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require az
require openssl

[ -n "$SUBSCRIPTION_ID" ] || SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
az account set --subscription "$SUBSCRIPTION_ID"

log "subscription: $SUBSCRIPTION_ID"
log "location:     $LOCATION"

# --- 1. stockage du state Terraform -----------------------------------------
log "resource group $TF_STATE_RG"
az group create --name "$TF_STATE_RG" --location "$LOCATION" -o none

SA=""
if [ -n "${TF_STATE_STORAGE_ACCOUNT:-}" ]; then
  SA="$TF_STATE_STORAGE_ACCOUNT"
else
  # Réutilise le compte de stockage créé par une exécution précédente du script.
  SA="$(az storage account list -g "$TF_STATE_RG" \
    --query "[?starts_with(name, 'tfstate')].name | [0]" -o tsv)"
  # Un résultat JMESPath vide est affiché comme la chaîne "None".
  if [ "$SA" = "None" ]; then
    SA=""
  fi
fi

if [ -z "$SA" ]; then
  for _ in 1 2 3 4 5; do
    CANDIDATE="tfstate$(openssl rand -hex 3)"
    if az storage account check-name --name "$CANDIDATE" --query nameAvailable -o tsv | grep -qx true; then
      SA="$CANDIDATE"
      break
    fi
  done
  [ -n "$SA" ] || die "could not find an available storage account name"
fi

log "storage account $SA"
if ! az storage account show -g "$TF_STATE_RG" -n "$SA" --query id -o tsv >/dev/null 2>&1; then
  az storage account create \
    --name "$SA" \
    --resource-group "$TF_STATE_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --https-only true \
    -o none
fi

log "blob versioning + 7 day soft delete"
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$TF_STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  -o none

log "container $STATE_CONTAINER"
if ! az storage container show --account-name "$SA" --name "$STATE_CONTAINER" --auth-mode login -o none 2>/dev/null; then
  az storage container create \
    --account-name "$SA" \
    --name "$STATE_CONTAINER" \
    --auth-mode login \
    -o none
fi

# --- 2. groupe de ressources de l'application --------------------------------
log "resource group $APP_RG"
az group create --name "$APP_RG" --location "$LOCATION" -o none

# --- 3. étapes suivantes -----------------------------------------------------
cat <<EOF

Bootstrap done. No Azure identity and no secret were created.

Terraform, from infra/ (the state lives in the account above):

  terraform init \\
    -backend-config="resource_group_name=$TF_STATE_RG" \\
    -backend-config="storage_account_name=$SA"
  terraform apply

Then, once the public FQDN is known:

  gh variable set DOMAIN --repo <owner>/<repo> --body "<dns_label>.$LOCATION.cloudapp.azure.com"
  gh secret set GRAFANA_ADMIN_PASSWORD --repo <owner>/<repo>

And install the self-hosted runner on the VM, with a token that expires in one hour:

  TOKEN=\$(gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token)
  az vm run-command invoke -g $APP_RG -n <vm-name> --command-id RunShellScript \\
    --scripts @scripts/runner-install.sh --parameters "<owner>/<repo>" "\$TOKEN"

EOF
