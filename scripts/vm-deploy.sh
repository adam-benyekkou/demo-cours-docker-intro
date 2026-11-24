#!/usr/bin/env bash
# Exécuté sur la VM par la CI, via `az vm run-command` (pas de port 22).
# Arguments attendus, sous la forme key=value :
#   image=<ref image taguée>  domain=<fqdn>  acme_email=<email>  env_b64=<fichier .env en base64>
set -euo pipefail

for arg in "$@"; do export "${arg}"; done
: "${image:?image manquante}"
: "${domain:?domain manquant}"
: "${env_b64:?env_b64 manquant}"

STACK_DIR=/opt/demo-stack
REPO_URL=https://github.com/adam-benyekkou/demo-cours-docker-intro.git

# cloud-init hands the clone to azureuser; run-command runs as root.
git config --global --add safe.directory "$STACK_DIR"

if [ -d "$STACK_DIR/.git" ]; then
    git -C "$STACK_DIR" fetch --prune origin main
    git -C "$STACK_DIR" reset --hard origin/main
else
    install -d -m 0755 "$STACK_DIR"
    git clone --branch main "$REPO_URL" "$STACK_DIR"
fi

umask 077
printf '%s' "$env_b64" | base64 -d > "$STACK_DIR/stack/.env"
chmod 600 "$STACK_DIR/stack/.env"

cd "$STACK_DIR"
docker compose --env-file stack/.env -f stack/docker-compose.yml pull
docker compose --env-file stack/.env -f stack/docker-compose.yml up -d --remove-orphans
docker image prune -f >/dev/null

docker compose --env-file stack/.env -f stack/docker-compose.yml ps
