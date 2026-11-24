# Démo — conteneurisation d'une application MVC sur Azure

Une application MVC factice derrière Traefik, avec Prometheus, Grafana,
cAdvisor et node_exporter pour l'observabilité. L'infrastructure (VM, réseau,
IP publique) est décrite en Terraform, et GitHub Actions la déploie à chaque
merge sur `main`.

## Accès

Domaine : `demo-cours-docker-adam.spaincentral.cloudapp.azure.com`

| Lien | Ce qu'on voit |
|---|---|
| <https://demo-cours-docker-adam.spaincentral.cloudapp.azure.com/> | Page « Bonjour depuis le conteneur » : nom du conteneur, version déployée, uptime, adresse client |
| <https://demo-cours-docker-adam.spaincentral.cloudapp.azure.com/health> | Sonde JSON, `{"status":"Healthy", ...}` |
| <https://demo-cours-docker-adam.spaincentral.cloudapp.azure.com/grafana/> | Grafana (`admin` + le mot de passe du secret `GRAFANA_ADMIN_PASSWORD`) |
| <https://demo-cours-docker-adam.spaincentral.cloudapp.azure.com/metrics> | **404 volontaire** : les métriques ne sont pas publiques |
| <https://github.com/adam-benyekkou/demo-cours-docker-intro/actions> | Historique des déploiements |

Les quatre dashboards sont dans le dossier « Démo Docker » de Grafana :

| Dashboard | Source | À regarder |
|---|---|---|
| Démo — Application (HTTP) | `/metrics` de l'appli | requêtes par code, latence p95 |
| Démo — Traefik | Traefik (`:8082`, interne) | trafic par routeur (`app`, `grafana`) |
| Démo — Hôte (node_exporter) | node_exporter | CPU, mémoire, disques, charge de la VM |
| Démo — Conteneurs (cAdvisor) | cAdvisor | CPU, mémoire, réseau par conteneur |

Pour générer du trafic visible :

```bash
for i in $(seq 1 200); do curl -s -o /dev/null https://demo-cours-docker-adam.spaincentral.cloudapp.azure.com/; done
```

## Les services

| Service | Rôle |
|---|---|
| `traefik` | Reverse proxy, TLS Let's Encrypt, routage par labels Docker |
| `app` | Application ASP.NET Core 10 : `/`, `/health`, `/metrics` |
| `prometheus` | Collecte des métriques, 15 jours de rétention |
| `grafana` | Dashboards, servi sous `/grafana/` |
| `cadvisor` | Métriques CPU / mémoire / réseau par conteneur |
| `node-exporter` | Métriques de l'hôte |

Prometheus, cAdvisor et node_exporter ne sont pas publiés sur Internet : la
seule entrée est Traefik, sur 80 et 443.

## Arborescence

```
app/      application ASP.NET Core et son Dockerfile
stack/    docker-compose.yml (six services), config Prometheus, dashboards Grafana
infra/    Terraform : VNet, NSG, IP publique, VM, disque /data, budget
scripts/  installation du runner GitHub Actions sur la VM
.github/  pr.yml (contrôles) et deploy.yml (déploiement sur main)
```

## Test local, sans Azure

```bash
cp stack/.env.example stack/.env     # DOMAIN=app.localhost, mot de passe au choix
docker compose --env-file stack/.env -f stack/docker-compose.yml -f stack/docker-compose.local.yml up -d --build
```

Ports `18080`/`18443` (les 80/443 de l'hôte sont souvent pris), certificat
auto-signé de Traefik. Les erreurs ACME dans les logs sont normales en local.

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: app.localhost' http://127.0.0.1:18080/   # 301
curl -fsk -H 'Host: app.localhost' https://127.0.0.1:18443/health                          # 200
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: app.localhost' https://127.0.0.1:18443/metrics  # 404
```

## Déploiement

Une fois, sur une souscription Azure vierge :

```bash
./infra/bootstrap/bootstrap.sh          # groupes de ressources + compte d'état

cd infra
cp terraform.tfvars.example terraform.tfvars   # renseigner admin_ssh_public_key
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=<tfstate-xxxxxx>"
terraform apply
cd ..

gh variable set DOMAIN --body "$(terraform -chdir=infra output -raw fqdn)"
gh secret   set GRAFANA_ADMIN_PASSWORD

TOKEN=$(gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token)
az vm run-command invoke -g rg-demo-docker -n democours-vm \
  --command-id RunShellScript --scripts @scripts/runner-install.sh \
  --parameters "<owner>/<repo>" "$TOKEN"
```

Ensuite, chaque push sur `main` déclenche `Deploy` sur le runner de la VM :
build de l'image, `up -d --build`, puis test de fumée HTTPS. Terraform est
appliqué à la main ; aucun identifiant Azure ne vit dans GitHub.

## Coût

La VM est facturée tant qu'elle est **allouée** : un arrêt depuis l'OS ne suffit
pas.

```bash
az vm deallocate -g rg-demo-docker -n democours-vm   # hors session de cours
```
