#!/usr/bin/env bash
#
# One-time (re-runnable) Azure bootstrap for the demo stack.
#
# Creates only what Terraform cannot create for itself:
#   - rg-tfstate + storage account + tfstate container (remote state)
#   - rg-demo-docker, the resource group that holds the whole stack
#
# No Azure identity is created: the CI runs on a self-hosted runner installed on
# the VM, so it never calls the Azure API. Terraform is applied by hand, with
# your own `az login`.
#
# Requires: az (logged in), openssl.

set -euo pipefail

# --- driver variables -------------------------------------------------------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
LOCATION="${LOCATION:-francecentral}"

TF_STATE_RG="rg-tfstate"
APP_RG="rg-demo-docker"
STATE_CONTAINER="tfstate"

# --- helpers ----------------------------------------------------------------
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

# --- 1. Terraform state storage ---------------------------------------------
log "resource group $TF_STATE_RG"
az group create --name "$TF_STATE_RG" --location "$LOCATION" -o none

SA=""
if [ -n "${TF_STATE_STORAGE_ACCOUNT:-}" ]; then
  SA="$TF_STATE_STORAGE_ACCOUNT"
else
  # Reuse the state account created by a previous run of this script.
  SA="$(az storage account list -g "$TF_STATE_RG" \
    --query "[?starts_with(name, 'tfstate')].name | [0]" -o tsv)"
  # An empty JMESPath result is printed as the string "None".
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

# --- 2. Application resource group ------------------------------------------
log "resource group $APP_RG"
az group create --name "$APP_RG" --location "$LOCATION" -o none

# --- 3. What comes next -----------------------------------------------------
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
