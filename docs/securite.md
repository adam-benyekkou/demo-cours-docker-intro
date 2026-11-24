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
- **OIDC.** L'environnement GitHub `production` n'accepte que le branchement
  `main` : une autre branche ne peut pas obtenir le jeton de déploiement.
  Aucun secret de client Azure n'existe.
- **`.env` de la VM.** Il voyage comme paramètre protégé de `run-command` : sa
  valeur n'apparaît ni dans les logs du job, ni dans l'historique de la commande.
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

- **cAdvisor garde un accès direct à `/var/run/docker.sock`.** Depuis la
  v0.53.0, sa fabrique Docker ouvre aussi le socket gRPC de containerd, qu'un
  proxy HTTP (`docker-socket-proxy`) ne peut pas fournir. Un cAdvisor compromis
  reste donc équivalent à root sur l'hôte. Le reste de la stack n'a pas cet
  accès.
- **Métriques par conteneur.** Elles dépendent du moteur Docker de l'hôte
  (cgroups v2, snapshotters containerd) : à vérifier sur la VM après un
  changement de version de Docker.
- **Pas de `CAP_SYSLOG` pour cAdvisor** (`cap_drop: ALL`). Sous Ubuntu, où
  `dmesg_restrict` vaut 1, la lecture de `/dev/kmsg` échoue et le watcher OOM est
  désactivé. Les métriques CPU / mémoire / réseau ne sont pas affectées.
- **Une PR du même dépôt obtient le jeton OIDC avec `Contributor`** sur le groupe
  de ressources : elle pourrait modifier le workflow. Acceptable tant qu'un seul
  auteur peut pousser ; sinon, une app registration en lecture seule pour les PR
  serait nécessaire.
- **Dimensionnement.** `Standard_B2s` (4 Go) héberge sept conteneurs :
  confortable pour la démo, juste si Grafana et l'application travaillent en même
  temps.
- **Let's Encrypt.** La première émission utilise la production ; en cas d'échecs
  répétés, basculer l'ACME sur le répertoire staging.
- **HSTS `preload`.** Le navigateur garde le domaine en HTTPS pendant un an : un
  retour en HTTP local sur ce nom échouera.
- **Pas d'email ACME.** Les certificats sont émis sans notification
  d'expiration. Pour en ajouter une, renseigner `certificatesResolvers.le.acme.email`
  dans `stack/traefik/traefik.yml` : la configuration statique est un fichier
  unique, Traefik refuse de la mélanger à des options CLI.
