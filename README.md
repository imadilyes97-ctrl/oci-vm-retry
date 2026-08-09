# OCI VM Retry — 24/7 sur GitHub Actions

Retente la création d'une **VM Oracle Cloud Ampere A1 (Marseille)** toutes les
**30 secondes**, **gratuitement et en continu**, sans que ton PC reste allumé.
Le retry tourne sur **GitHub Actions** (dépôt public = minutes illimitées).

Dès que la capacité Oracle revient, la VM est créée automatiquement et tu reçois
une **notification** (ntfy.sh). Plus rien à faire.

## Comment ça marche

```
GitHub Actions (public)  ──boucle toutes les 30s──▶  OCI API (Marseille)
      │                                                   │
      └── si "Out of host capacity" → retente (toutes les 30s)
      └── si succès → VM créée → notification ntfy.sh → arrêt
      └── si timeout 330 min → se re-déclenche automatiquement
```

- **Dépôt public** → minutes GitHub Actions illimitées (gratuit).
- **Toutes les clés/identifiants OCI** → en GitHub Secrets, jamais en clair.
- **Workflow** : `workflow_dispatch` + cron toutes les 6h (secours), se
  re-déclenche lui-même avant le timeout (auto-relais sans interruption).

## Setup (une seule fois, ~2 min)

1. **Installer gh** (déjà fait par JARVIS si tu es sur ce PC) :
   ```
   winget install --id GitHub.cli
   ```
2. **Te connecter** à GitHub :
   ```
   gh auth login
   ```
   → choisis *GitHub.com* → *HTTPS* → *Login with a web browser*.

3. **Lancer le setup** (crée le dépôt public, configure les secrets, lance le 1er run) :
   ```
   bash setup-github.sh
   ```

C'est tout. Le premier run démarre automatiquement.

## S'abonner à la notification ntfy.sh

Le topic est affiché par `setup-github.sh` (ex: `oci-rdp-xxxxxxxx`). Pour être
notifié quand la VM est créée :

- **Téléphone** : installe l'app **ntfy** (Play Store / App Store), ajoute le
  topic, active les notifications.
- **Navigateur** : ouvre `https://ntfy.sh/<topic>` (garde l'onglet ouvert ou
  active les notifications du site).
- **Desktop** : l'app ntfy desktop, ou `ntfy subscribe <topic>`.

Tu seras notifié dès que la VM est créée : *« VM Oracle RDP créée ! OCID: … »*.

## Suivre les runs

| Action | Commande |
|--------|----------|
| Suivre un run en direct | `gh run watch` |
| Liste des runs | `gh run list` |
| Logs en ligne | https://github.com/<toi>/oci-vm-retry/actions |
| Relancer manuellement | `gh workflow run oci-retry.yml` |

## Vérifier le premier relais (important — à faire 1 fois)

Le workflow se re-déclenche à ~330 min pour ne jamais s'arrêter. **Avant de
laisser tourner sans surveillance**, vérifie après ~5h30 que le relais
fonctionne :

1. Ouvre https://github.com/<toi>/oci-vm-retry/actions
2. Tu dois voir **2 runs consécutifs** (le 2e lancé par le 1er à ~330 min).
3. Si le 2e run apparaît → le système tourne 24/7 tout seul. ✅

## Après la création de la VM

Le retry s'arrête tout seul (la VM existe → notification → fin). Il ne reste
qu'à te connecter : la config RDP complète (xRDP + XFCE + Claude Code) est
préparée dans `~/Desktop/oci-rdp/` (le pipeline local `orchestrate-rdp.sh`
prend le relais une fois la VM joignable).

## Fichiers

```
.github/workflows/oci-retry.yml   ← le workflow (retry + auto-relais)
scripts/oci-retry.sh              ← la boucle de retry (30s)
setup-github.sh                   ← setup 1 fois (repo + secrets + run)
```
