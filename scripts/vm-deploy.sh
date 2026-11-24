#!/usr/bin/env bash
# Runs on the VM through `az vm run-command` (no SSH port is open).
# Arguments are key=value pairs and this list is closed:
#   image=<registry ref>   sha=<40-char commit>   domain=<public FQDN>
#   repo=<clone URL>       run=<unique nonce>
#   env_b64=<.env, base64: sent as an Azure protected parameter>
#
# `run` is never read: it only makes the run-command body differ on every CI
# run, because `az vm run-command update` re-executes the script only when the
# body changes.
set -euo pipefail

export HOME="${HOME:-/root}"

fail() {
    printf 'deploy: %s\n' "$*" >&2
    exit 1
}

# Azure exposes run-command parameters either as environment variables (managed
# run command) or as positional arguments; accept both, and only these names.
for arg in "$@"; do
    case "$arg" in
        image=*|sha=*|domain=*|env_b64=*|repo=*|run=*) export "${arg%%=*}=${arg#*=}" ;;
        *) fail "unexpected argument: ${arg%%=*}" ;;
    esac
done

: "${image:?image missing}"
: "${sha:?sha missing}"
: "${domain:?domain missing}"
: "${env_b64:?env_b64 missing}"

[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "sha is not a full commit id: $sha"

STACK_DIR=/opt/demo-stack
REPO_URL="${repo:-https://github.com/adam-benyekkou/demo-cours-docker-intro.git}"

# cloud-init hands the clone to azureuser; run-command runs as root.
git config --global --get-all safe.directory 2>/dev/null | grep -qx "$STACK_DIR" \
    || git config --global --add safe.directory "$STACK_DIR"

# Terraform returns as soon as the VM exists: wait for cloud-init and Docker.
if ! command -v docker >/dev/null 2>&1; then
    cloud-init status --wait || true
fi
for _ in $(seq 1 60); do
    command -v docker >/dev/null 2>&1 && break
    sleep 5
done
command -v docker >/dev/null 2>&1 || fail "docker is not installed yet"

# The data disk is attached by a separate Terraform resource: retry the mount.
if [ -x /usr/local/sbin/setup-data-disk.sh ] && ! mountpoint -q /data; then
    /usr/local/sbin/setup-data-disk.sh || true
fi
mountpoint -q /data || fail "/data is not mounted"

if [ ! -d "$STACK_DIR/.git" ]; then
    install -d -m 0755 "$STACK_DIR"
    git clone --branch main "$REPO_URL" "$STACK_DIR"
fi
git -C "$STACK_DIR" fetch --prune origin +refs/heads/main:refs/remotes/origin/main

# Deploy exactly the commit whose image was built. Never drift to origin/main.
git -C "$STACK_DIR" merge-base --is-ancestor "$sha" origin/main \
    || fail "commit $sha is not an ancestor of origin/main"
git -C "$STACK_DIR" reset --hard "$sha"

umask 077
printf '%s' "$env_b64" | base64 -d > "$STACK_DIR/stack/.env"
chmod 600 "$STACK_DIR/stack/.env"
grep -q '^DOMAIN=' "$STACK_DIR/stack/.env" || fail ".env has no DOMAIN"
grep -q '^GRAFANA_ADMIN_PASSWORD=' "$STACK_DIR/stack/.env" || fail ".env has no GRAFANA_ADMIN_PASSWORD"

# Grafana reads its admin password from a mounted file, never from the
# container environment, so `docker inspect` never carries the value.
install -d -m 0755 "$STACK_DIR/stack/secrets"
grep -m1 '^GRAFANA_ADMIN_PASSWORD=' "$STACK_DIR/stack/.env" | cut -d= -f2- \
    > "$STACK_DIR/stack/secrets/grafana_admin_password"
chown 472:472 "$STACK_DIR/stack/secrets/grafana_admin_password"
chmod 0400 "$STACK_DIR/stack/secrets/grafana_admin_password"

cd "$STACK_DIR"
compose=(docker compose --env-file stack/.env -f stack/docker-compose.yml)
"${compose[@]}" pull
"${compose[@]}" up -d --remove-orphans
docker image prune -f >/dev/null

"${compose[@]}" ps
