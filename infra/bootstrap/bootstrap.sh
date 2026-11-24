#!/usr/bin/env bash
#
# One-time (re-runnable) Azure bootstrap for the demo stack.
#
# Creates:
#   - rg-tfstate + storage account (remote Terraform state) + tfstate container
#   - rg-demo-docker (holds the stack, created by terraform)
#   - an Entra app registration + service principal with two federated
#     credentials (GitHub OIDC, no client secret) and the two role assignments
#   - a consumption budget when the CLI supports it (otherwise terraform does)
#
# Nothing secret is created or echoed: authentication is OIDC only.

set -euo pipefail

# --- driver variables -------------------------------------------------------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
LOCATION="${LOCATION:-francecentral}"
GH_REPO="${GH_REPO:-adam-benyekkou/demo-cours-docker-intro}"
APP_NAME="${APP_NAME:-demo-docker-cours-gh}"

TF_STATE_RG="rg-tfstate"
APP_RG="rg-demo-docker"
STATE_CONTAINER="tfstate"
FED_MAIN_NAME="gh-main"
FED_PR_NAME="gh-pr"
FED_ENV_NAME="gh-env-production"
FED_ISSUER="https://token.actions.githubusercontent.com"
FED_AUDIENCE="api://AzureADTokenExchange"

# --- helpers ----------------------------------------------------------------
log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
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
TENANT_ID="$(az account show --query tenantId -o tsv)"

az account set --subscription "$SUBSCRIPTION_ID"

log "subscription: $SUBSCRIPTION_ID"
log "tenant:       $TENANT_ID"
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

APP_RG_ID="$(az group show -n "$APP_RG" --query id -o tsv)"
SA_ID="$(az storage account show -g "$TF_STATE_RG" -n "$SA" --query id -o tsv)"

# --- 3. Entra app registration + federation ---------------------------------
APP_ID="$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)"
if [ -z "$APP_ID" ] || [ "$APP_ID" = "None" ]; then
  APP_ID=""
  log "app registration $APP_NAME"
  APP_ID="$(az ad app create \
    --display-name "$APP_NAME" \
    --sign-in-audience AzureADMyOrg \
    --query appId -o tsv)"
else
  log "app registration $APP_NAME (existing: $APP_ID)"
fi

SP_OBJECT_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)"
if [ -z "$SP_OBJECT_ID" ] || [ "$SP_OBJECT_ID" = "None" ]; then
  log "service principal"
  az ad sp create --id "$APP_ID" -o none
  SP_OBJECT_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)"
fi
if [ -z "$SP_OBJECT_ID" ] || [ "$SP_OBJECT_ID" = "None" ]; then
  die "could not resolve the service principal object id"
fi

add_federated_credential() {
  local name="$1"
  local subject="$2"

  if az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'].name" -o tsv | grep -qx "$name"; then
    log "federated credential $name (existing)"
    return 0
  fi

  log "federated credential $name"
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"$FED_ISSUER\",
    \"subject\": \"$subject\",
    \"audiences\": [\"$FED_AUDIENCE\"]
  }" -o none
}

add_federated_credential "$FED_MAIN_NAME" "repo:${GH_REPO}:ref:refs/heads/main"
add_federated_credential "$FED_PR_NAME" "repo:${GH_REPO}:pull_request"
# Jobs that declare `environment: production` get this subject, not ref:refs/heads/main.
add_federated_credential "$FED_ENV_NAME" "repo:${GH_REPO}:environment:production"

# --- 4. Role assignments ----------------------------------------------------
assign_role() {
  local role="$1"
  local scope="$2"

  if [ -n "$(az role assignment list --assignee-object-id "$SP_OBJECT_ID" --scope "$scope" \
    --query "[?roleDefinitionName=='$role'].id" -o tsv)" ]; then
    log "role $role (existing)"
    return 0
  fi

  log "role $role"
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$scope" \
    -o none
}

assign_role "Contributor" "$APP_RG_ID"
assign_role "Storage Blob Data Contributor" "$SA_ID"

# --- 5. GitHub configuration ------------------------------------------------
cat <<EOF

Bootstrap done. No secret was created: GitHub authenticates with OIDC.

Set these repository variables (then let terraform read the state below):

  gh variable set AZURE_CLIENT_ID --repo $GH_REPO --body "$APP_ID"
  gh variable set AZURE_TENANT_ID --repo $GH_REPO --body "$TENANT_ID"
  gh variable set AZURE_SUBSCRIPTION_ID --repo $GH_REPO --body "$SUBSCRIPTION_ID"
  gh variable set TF_STATE_RESOURCE_GROUP --repo $GH_REPO --body "$TF_STATE_RG"
  gh variable set TF_STATE_STORAGE_ACCOUNT --repo $GH_REPO --body "$SA"

Set the alert recipients as a Terraform list (enables the budget in infra/budget.tf):

  gh variable set BUDGET_CONTACT_EMAILS --repo $GH_REPO --body '["you@example.com"]'

Make the GHCR package readable by the VM (no registry login on the host):

  gh api -X PATCH /user/packages/container/demo-cours-docker-intro%2Fapp -f visibility=public

Set the Grafana admin password (the prompt keeps it out of the shell history):

  gh secret set GRAFANA_ADMIN_PASSWORD --repo $GH_REPO

Terraform backend settings for the CI init step:

  resource_group_name  = $TF_STATE_RG
  storage_account_name = $SA
  container_name       = $STATE_CONTAINER
  key                  = demo-cours-docker-intro.tfstate
  use_oidc             = true
  use_azuread_auth     = true

EOF
