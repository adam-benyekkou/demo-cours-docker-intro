#!/usr/bin/env bash
# Prépare le test local : certificat auto-signé + provider fichiers local.
# La config dynamique de prod est copiée et complétée par le certificat.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/tls"
dyn="$here/traefik/local-dynamic"

mkdir -p "$out" "$dyn"

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "$out/local.key" -out "$out/local.crt" \
    -subj "/CN=app.localhost" \
    -addext "subjectAltName=DNS:app.localhost,DNS:localhost,IP:127.0.0.1" 2>/dev/null
chmod 600 "$out/local.key"

cp "$here"/traefik/dynamic/*.yml "$dyn"/
cat > "$dyn/99-local-tls.yml" <<'YAML'
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /certs/local.crt
        keyFile: /certs/local.key
YAML

echo "certificat local : $out/local.crt"
echo "config dynamique : $dyn"
