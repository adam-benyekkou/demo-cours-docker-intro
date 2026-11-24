#!/usr/bin/env bash
# runner-install.sh — installe le runner GitHub Actions self-hosted sur la VM.
#
# Lancé une fois, en root, via `az vm run-command` : c'est lui qui enregistre le
# runner que deploy.yml utilise ensuite. On y revient quand la version du runner
# ou ses prérequis changent. Il ne touche ni au dépôt ni aux workflows.
#
#   runner-install.sh <owner/repo> <registration-token> [labels]
#
# `az vm run-command invoke` passe les valeurs des paramètres en positionnel et
# perd leurs noms : les arguments sont donc positionnels à dessein.
# Le token est un token d'enregistrement, valable une heure, obtenu avec :
#   gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token
set -euo pipefail

RUNTIME_VERSION="2.338.2"
RUNNER_USER="ghrunner"
RUNNER_DIR="/data/actions-runner"
repo="${1:-}"
token="${2:-}"
LABELS="${3:-democours}"

: "${repo:?repo is required}"
: "${token:?token is required}"

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "runner-install: bad repo name" >&2; exit 2; }
mountpoint -q /data || { echo "runner-install: /data is not mounted" >&2; exit 1; }
id -u "$RUNNER_USER" >/dev/null 2>&1 || { echo "runner-install: user $RUNNER_USER is missing" >&2; exit 1; }

tarball="actions-runner-linux-x64-${RUNTIME_VERSION}.tar.gz"
url="https://github.com/actions/runner/releases/download/v${RUNTIME_VERSION}/${tarball}"

install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$RUNNER_DIR"
if [ ! -f "$RUNNER_DIR/run.sh" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "$url" -o "$tmp/$tarball"
    tar -xzf "$tmp/$tarball" -C "$RUNNER_DIR"
    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
fi

# Les scripts du runner exigent d'être lancés depuis sa racine.
cd "$RUNNER_DIR"

# libicu et compagnie : le runner est un binaire .NET et en a besoin.
./bin/installdependencies.sh >/dev/null

# config.sh refuse un runner déjà configuré ; pour le réenregistrer, le supprimer
# d'abord (`./config.sh remove --token <removal-token>`) ou effacer
# /data/actions-runner/.runner.
if [ ! -f .runner ]; then
    sudo -u "$RUNNER_USER" ./config.sh \
        --unattended \
        --url "https://github.com/$repo" \
        --token "$token" \
        --labels "$LABELS" \
        --work "${RUNNER_DIR}/_work" \
        --name "$(hostname)"
fi

./svc.sh status >/dev/null 2>&1 || ./svc.sh install "$RUNNER_USER" >/dev/null
./svc.sh start >/dev/null 2>&1 || true
./svc.sh status || true

echo "runner installed: labels=$LABELS user=$RUNNER_USER work=${RUNNER_DIR}/_work"
