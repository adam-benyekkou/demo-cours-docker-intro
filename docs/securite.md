# Sécurité et limites

Ce que la stack protège, et ce qu'elle ne protège pas. Les décisions
d'architecture correspondantes sont dans [exploitation.md](exploitation.md).

## Mesures en place

- **Surface réseau.** Le NSG n'ouvre que 80 et 443 entrants ; aucun port
  d'administration n'est exposé. Prometheus, cAdvisor, node_exporter et le
  dashboard Traefik ne sont sur aucun réseau publié.
- **Socket Docker.** Traefik n'y accède qu'à travers
  `tecnativa/docker-socket-proxy` en lecture seule (`POST=0`), sur le réseau
  interne `socket` où aucune application n'est présente.
- **Aucun identifiant Azure dans GitHub.** Ni secret client, ni OIDC, ni clé SSH :
  le déploiement s'exécute sur un runner installé sur la VM et ne parle jamais à
  l'API Azure.
- **Le runner ne sert qu'à `push` sur `main`** et `workflow_dispatch`. Les
  contrôles de PR tournent sur `ubuntu-latest` : une PR n'atteint jamais la VM.
- **`.env` de la VM.** Écrit par le workflow dans `stack/.env` (0600), jamais
  commité ; le mot de passe Grafana vient du secret GitHub.
- **Mot de passe Grafana.** Grafana le lit dans un fichier monté (`/run/secrets`,
  0400) : il n'est jamais dans l'environnement du conteneur, donc jamais dans
  `docker inspect`.
- **En-têtes.** HSTS, `nosniff`, `frameDeny`, `referrerPolicy` et une limite de
  débit sur Grafana : `stack/traefik/dynamic/security.yml`. Pas de CSP : les
  pages Grafana utilisent scripts et styles inline.
- **Conteneurs.** `cap_drop: ALL`, `no-new-privileges`, `read_only` + `tmpfs` sur
  les services applicatifs ; Traefik ne garde que `NET_BIND_SERVICE`.
- **`/metrics`.** Le routeur public l'exclut. Prometheus appelle l'application
  directement sur le réseau Docker, et le test de fumée vérifie que le chemin
  public répond 404.
- **Dashboard Traefik.** Désactivé (`api` absent de `traefik.yml`) : il ne reste
  que l'endpoint de santé interne.
- **État Terraform.** Compte de stockage versionné, sans clé de compte
  (`use_azuread_auth`), avec un rôle `Storage Blob Data Contributor` limité à ce
  compte.
- **Scan.** `trivy config` bloque la CI sur les misconfigurations
  HIGH/CRITICAL. Les exceptions assumées vivent dans `.trivyignore.yaml`, chacune
  avec sa justification.

## Limites connues

- **cAdvisor est figé en v0.52.0.** Il lit les conteneurs à travers le
  socket-proxy et ne monte aucun socket, ce qui évite qu'un cAdvisor compromis
  soit root sur l'hôte. Dès la v0.53.0, sa fabrique Docker exige aussi le socket
  gRPC de containerd, qu'un proxy HTTP ne peut pas fournir : monter cette version
  redonnerait un accès root à cAdvisor. Dependabot ignore donc ces versions.
- **Les noms de conteneurs demandent le stockage Docker `overlay2`.** Docker 29
  active par défaut le snapshotter containerd, avec lequel cAdvisor ne retrouve
  pas la couche inscriptible des conteneurs : le dashboard « Conteneurs » reste
  alors vide. `infra/cloud-init.yml` écrit `/etc/docker/daemon.json` pour la VM.
  En test local, le même réglage est nécessaire dans Docker, sinon ce dashboard
  est vide ; l'hôte, Traefik et l'application ne sont pas touchés.
- **Pas de `CAP_SYSLOG` pour cAdvisor** (`cap_drop: ALL`). Sous Ubuntu, où
  `dmesg_restrict` vaut 1, la lecture de `/dev/kmsg` échoue et le watcher OOM est
  désactivé. Les métriques CPU / mémoire / réseau ne sont pas affectées.
- **Le runner exécute le code mergé sur `main`, avec accès au socket Docker**,
  donc root sur la VM. GitHub déconseille les runners auto-hébergés sur un dépôt
  public : c'est acceptable tant qu'un seul auteur merge et qu'aucun workflow
  `pull_request` ne cible le runner. Ne jamais changer cette règle.
- **Recréer la VM efface le runner** : relancer `scripts/runner-install.sh` avec
  un nouveau token.
- **L'image n'est archivée nulle part** : elle n'existe que sur la VM.
- **`terraform plan` n'est plus commenté dans les PR** : il demande l'état
  distant et un jeton Azure, que la CI n'a plus. À lancer à la main.
- **Dimensionnement.** `Standard_D2s_v4` (2 vCPU, 8 Go) héberge sept conteneurs
  et les builds .NET : confortable pour la démo.
- **Let's Encrypt.** La première émission utilise la production ; en cas d'échecs
  répétés, basculer l'ACME sur le répertoire staging.
- **HSTS `preload`.** Le navigateur garde le domaine en HTTPS pendant un an : un
  retour en HTTP local sur ce nom échouera.
- **Pas d'email ACME.** Les certificats sont émis sans notification
  d'expiration. Pour en ajouter une, renseigner `certificatesResolvers.le.acme.email`
  dans `stack/traefik/traefik.yml` : la configuration statique est un fichier
  unique, Traefik refuse de la mélanger à des options CLI.
