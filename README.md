# Démo — conteneurisation d'une application MVC sur Azure

Une application MVC factice, conteneurisée et servie par Traefik, avec
Prometheus, Grafana, cAdvisor et node_exporter pour l'observabilité.
L'infrastructure est décrite en Terraform, et GitHub Actions déploie sur la VM
depuis un runner auto-hébergé installé dessus, à chaque merge sur `main`.

## Ce que la démo montre

| Brique | Rôle | Où |
|---|---|---|
| Application MVC (ASP.NET Core 10) | Page d'accueil, `/health`, `/metrics` | `app/` |
| Traefik v3 | Reverse proxy, TLS Let's Encrypt, routage par labels Docker | `stack/docker-compose.yml` |
| Prometheus | Collecte des métriques (5 cibles) | `stack/prometheus/` |
| Grafana | 4 dashboards provisionnés, sous `/grafana/` | `stack/grafana/` |
| cAdvisor | Métriques CPU / mémoire / réseau par conteneur | `stack/docker-compose.yml` |
| node_exporter | Métriques de l'hôte : CPU, mémoire, disques, charge | `stack/docker-compose.yml` |
| Terraform | VNet, NSG, IP publique, VM, disque `/data`, budget | `infra/` |
| Runner auto-hébergé | Construit l'image et démarre la stack depuis la VM | `scripts/runner-install.sh` |
| GitHub Actions | Contrôles en PR, déploiement sur `main` | `.github/workflows/` |

## Carte du dépôt

```
.
├── app/                         application ASP.NET Core, l'image déployée
│   ├── Dockerfile               build multi-étapes, utilisateur non-root
│   └── Program.cs               pipeline HTTP, /health, /metrics
├── stack/                       ce qui tourne sur la VM
│   ├── docker-compose.yml       les six services, Traefik configuré en flags
│   ├── docker-compose.local.yml surcharge du test local (ports 18080/18443)
│   ├── .env.example             contrat unique : domaine, mot de passe, version
│   ├── prometheus/              configuration de collecte
│   └── grafana/                 provisioning et quatre dashboards
├── infra/                       infrastructure Azure (Terraform)
│   ├── bootstrap/bootstrap.sh   à lancer une fois : compte d'état et groupes de ressources
│   ├── versions.tf, backend.tf  versions et état distant
│   ├── variables.tf             toutes les variables et leurs valeurs par défaut
│   ├── network.tf, vm.tf, disk.tf  VNet, NSG, IP publique, VM, disque /data
│   ├── cloud-init.yml           préparation de l'hôte au premier démarrage
│   └── budget.tf                alerte de consommation à 50 / 90 / 100 %
├── scripts/runner-install.sh    installe le runner auto-hébergé sur la VM
└── .github/workflows/           pr.yml (contrôles) et deploy.yml (déploiement)
```

## Ce qui a été simplifié, et ce que ça coûte

La stack est passée de sept services à six, et de quatre fichiers de
configuration Traefik à aucun : les entrypoints, ACME et les métriques sont des
flags `command:` dans le compose. Les réseaux épinglés, les ancres de
durcissement, `read_only`, `cap_drop`, l'utilisateur `HOME=/tmp` et le
`socket-proxy` ont disparu, ainsi que `docs/`, `scripts/check-yaml.py` et
`stack/local-tls.sh`.

Conséquences assumées :

- Traefik et cAdvisor montent `docker.sock` directement : un conteneur compromis
  est root sur l'hôte.
- Le mot de passe Grafana est une variable d'environnement du conteneur, donc
  visible dans `docker inspect`.
- Plus d'en-têtes de sécurité (HSTS, `nosniff`, `frameDeny`) ni de limite de débit
  sur Grafana.
- Les conteneurs ne sont plus en lecture seule.

## Prérequis

- Une souscription Azure et la CLI `az` connectée (`az login`).
- `terraform >= 1.9`, `docker` avec le plugin compose, `gh` authentifié.
- Une clé SSH publique : Azure exige une méthode d'authentification sur la VM,
  même sans port 22 ouvert. Elle ne sert qu'en secours.
- Un dépôt GitHub public : les workflows lisent `vars.*`, aucun secret en clair.

## Mise en route

```bash
./infra/bootstrap/bootstrap.sh          # une fois : groupes de ressources + état

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

Un push sur `main` déclenche `Deploy` : build de l'image par le compose,
`up -d --build --remove-orphans`, puis test de fumée HTTPS. Terraform est appliqué
à la main, avec ton propre `az login` ; aucun identifiant Azure ne vit dans
GitHub.

## Explorer les services

Tout passe par `https://<DOMAIN>`. Le certificat Let's Encrypt est émis à la
première requête ; un avertissement de certificat dans les premières minutes est
le certificat par défaut de Traefik, il suffit de recharger.

| URL | Attendu |
|---|---|
| `/` | 200, « Bonjour depuis le conteneur » : nom du conteneur, version = SHA du commit, uptime |
| `/health` | 200, `{"status":"Healthy", ...}` |
| `/metrics` | **404** : volontairement fermé au public |
| `/grafana/` | 200, utilisateur `admin`, mot de passe = secret GitHub |
| `/grafana/metrics` | pas 200 : désactivées |

Quatre dashboards sont dans le dossier « Démo Docker » de Grafana : application
(HTTP), Traefik, hôte (node_exporter) et conteneurs (cAdvisor). Prometheus,
cAdvisor et node_exporter ne sont pas publiés ; pour interroger Prometheus :

```bash
az vm run-command invoke -g rg-demo-docker -n democours-vm --command-id RunShellScript \
  --scripts "docker exec demo-stack-prometheus-1 wget -qO- 'http://127.0.0.1:9090/api/v1/targets'" \
  --query 'value[0].message' -o tsv
```

Les cinq cibles (`app`, `traefik`, `cadvisor`, `node`, `prometheus`) doivent être
`up`.

## Test local, sans Azure

```bash
cp stack/.env.example stack/.env     # DOMAIN=app.localhost, mot de passe au choix
docker compose --env-file stack/.env -f stack/docker-compose.yml -f stack/docker-compose.local.yml up -d --build
```

La surcharge locale utilise des volumes nommés et les ports `18080`/`18443` (les
ports 80/443 de l'hôte sont souvent pris par d'autres conteneurs de cours), et
Traefik sert son certificat auto-signé. Les logs de Traefik affichent des erreurs
ACME : le résolveur `le` essaie d'émettre pour `app.localhost` et échoue, sans
conséquence.

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: app.localhost' http://127.0.0.1:18080/   # 301
curl -fsk -H 'Host: app.localhost' https://127.0.0.1:18443/health                          # 200
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: app.localhost' https://127.0.0.1:18443/metrics  # 404
```

cAdvisor monte `/var/run/docker.sock` **et** `/run/containerd/containerd.sock` :
Docker 29 utilise par défaut le snapshotter containerd et, sans le second socket,
les conteneurs n'ont pas de nom dans le dashboard. Sur la VM, `cloud-init` désactive
en plus le snapshotter (`/etc/docker/daemon.json`).

## Coûts

Facturation à l'usage : la VM est facturée tant qu'elle est **allouée**. Un arrêt
depuis l'OS ne suffit pas.

```bash
az vm deallocate -g rg-demo-docker -n democours-vm   # hors session de cours
```

`infra/budget.tf` alerte à 50 % et 90 % du réalisé, et à 100 % du prévisionnel :
c'est une alerte, pas un plafond.

## Dépannage

| Symptôme | Piste |
|---|---|
| `terraform apply` : `SkuNotAvailable` | Abonnement étudiant : cinq régions seulement, voir `infra/variables.tf` |
| `terraform init` : 403 | `Storage Blob Data Contributor` sur le compte d'état ; la propagation prend quelques minutes |
| Le workflow `Deploy` reste en attente | Runner hors ligne : `gh api repos/<owner>/<repo>/actions/runners` puis relancer `runner-install.sh` |
| Traefik renvoie 404 sur le domaine | `docker compose logs traefik` : labels absents ou provider Docker muet |
| Certificat Let's Encrypt en échec | Le DNS doit résoudre avant l'émission ; les logs Traefik nomment le challenge |
| Grafana en 502 au premier démarrage | Migrations SQLite : environ 30 s avant que le port 3000 réponde |
| Dashboard « Conteneurs » vide | Socket containerd absent, ou snapshotter actif sans le socket : voir la section locale |
| La VM n'a ni Docker ni `/data` | `custom_data` ignoré : `infra/cloud-init.yml` doit commencer par `#cloud-config` |

## Conventions

- **Langue.** Ce README et `stack/` sont en français. `infra/`, `scripts/`,
  `.github/` et `app/` commentent en anglais, comme le code qu'ils accompagnent.
- **Un fait, un endroit.** Les commandes `gh` ne vivent que dans la sortie de
  `bootstrap.sh`.
- **Une vérification locale.** `docker compose ... config -q` valide le compose,
  `terraform -chdir=infra fmt -check -recursive` tient le HCL aligné, et la CI
  passe Trivy sur l'image et sur `infra/`.
