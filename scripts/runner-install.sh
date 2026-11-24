#!/usr/bin/env bash
# Installs (or reinstalls) the GitHub Actions self-hosted runner on this VM.
# One shot, run as root through `az vm run-command`:
#
#   runner-install.sh <owner/repo> <registration-token> [labels]
#
# `az vm run-command invoke` passes parameter values positionally and drops
# their names, so the arguments are positional on purpose.
#
# The token is a registration token, valid for one hour, obtained with:
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

# The runner scripts insist on being started from the runner root.
cd "$RUNNER_DIR"

# libicu and friends: the runner is a .NET build and needs them.
./bin/installdependencies.sh >/dev/null

# config.sh refuses an already configured runner; to re-register, remove it first
# (`./config.sh remove --token <removal-token>`) or delete /data/actions-runner/.runner.
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
