#!/usr/bin/env bash
# Exécuté sur la VM par la CI, via `az vm run-command` (pas de port 22).
# Arguments key=value : image=<ref>, sha=<commit>, domain=<fqdn>, env_b64=<.env en base64>
set -euo pipefail

export HOME="${HOME:-/root}"

for arg in "$@"; do
    case "$arg" in
        *=*) export "${arg%%=*}=${arg#*=}" ;;
        *) : ;;
    esac
done

: "${image:?image manquante}"
: "${sha:?sha manquant}"
: "${domain:?domain manquant}"
: "${env_b64:?env_b64 manquant}"

STACK_DIR=/opt/demo-stack
REPO_URL=https://github.com/adam-benyekkou/demo-cours-docker-intro.git

# cloud-init hands the clone to azureuser; run-command runs as root.
git config --global --add safe.directory "$STACK_DIR"

# Terraform returns as soon as the VM exists: wait for cloud-init and Docker.
if ! command -v docker >/dev/null 2>&1; then
    cloud-init status --wait || true
fi
for _ in $(seq 1 60); do
    command -v docker >/dev/null 2>&1 && break
    sleep 5
done
command -v docker >/dev/null 2>&1 || { echo "docker is not installed yet" >&2; exit 1; }

# The data disk is attached by a separate Terraform resource: retry the mount.
if [ -x /usr/local/sbin/setup-data-disk.sh ] && ! mountpoint -q /data; then
    /usr/local/sbin/setup-data-disk.sh || true
fi
mountpoint -q /data || { echo "/data is not mounted" >&2; exit 1; }

if [ -d "$STACK_DIR/.git" ]; then
    git -C "$STACK_DIR" fetch --prune origin main
else
    install -d -m 0755 "$STACK_DIR"
    git clone --branch main "$REPO_URL" "$STACK_DIR"
    git -C "$STACK_DIR" fetch --prune origin main
fi

# Deploy exactly the commit whose image was built, not whatever main became.
if git -C "$STACK_DIR" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    git -C "$STACK_DIR" reset --hard "$sha"
else
    echo "commit $sha absent from the clone, falling back to origin/main" >&2
    git -C "$STACK_DIR" reset --hard origin/main
fi

umask 077
printf '%s' "$env_b64" | base64 -d > "$STACK_DIR/stack/.env"
chmod 600 "$STACK_DIR/stack/.env"

cd "$STACK_DIR"
docker compose --env-file stack/.env -f stack/docker-compose.yml pull
docker compose --env-file stack/.env -f stack/docker-compose.yml up -d --remove-orphans
docker image prune -f >/dev/null

docker compose --env-file stack/.env -f stack/docker-compose.yml ps
