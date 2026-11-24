#!/usr/bin/env bash
# Prépare le test local : certificat auto-signé, secret Grafana et provider
# fichiers local. La config dynamique de prod est copiée et complétée par le
# certificat.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/tls"
dyn="$here/traefik/local-dynamic"
sec_dir="$here/secrets"
sec="$sec_dir/grafana_admin_password"

mkdir -p "$out" "$dyn" "$sec_dir"

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "$out/local.key" -out "$out/local.crt" \
    -subj "/CN=app.localhost" \
    -addext "subjectAltName=DNS:app.localhost,DNS:localhost,IP:127.0.0.1" 2>/dev/null
# Traefik tourne sans CAP_DAC_OVERRIDE : la clé doit rester lisible par le
# conteneur. Certificat jetable, limité à localhost.
chmod 644 "$out/local.key"

# docker compose monte le mot de passe Grafana depuis un fichier, jamais depuis
# l'environnement du conteneur. Grafana tourne en uid 472 : le fichier doit être
# lisible par un autre utilisateur que le propriétaire local.
if grep -q '^GRAFANA_ADMIN_PASSWORD=' "$here/.env" 2>/dev/null; then
    grep -m1 '^GRAFANA_ADMIN_PASSWORD=' "$here/.env" | cut -d= -f2- > "$sec"
elif [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    printf '%s' "$GRAFANA_ADMIN_PASSWORD" > "$sec"
else
    openssl rand -hex 16 > "$sec"
    echo "avertissement : GRAFANA_ADMIN_PASSWORD absent, mot de passe local aléatoire" >&2
fi
chmod 644 "$sec"

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
echo "secret Grafana : $sec"
