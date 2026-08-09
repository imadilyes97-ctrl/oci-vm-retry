#!/usr/bin/env bash
# ============================================================
# SETUP — crée le dépôt public + secrets + lance le 1er run.
# À lancer UNE FOIS après : gh auth login (voir README).
# Lit les valeurs OCI depuis les fichiers locaux EXISTANTS et
# les met en GitHub Secrets — JAMAIS affichées ni commitées.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"
REPO="imadilyes97-ctrl/oci-vm-retry"
SRC="$HOME/Desktop/oci-rdp"
CONFIG="$HOME/.oci/config"
KEY="$HOME/.oci/oci_api_key.pem"

# gh via chemin complet (Windows) sinon PATH
GH="/c/Program Files/GitHub CLI/gh.exe"
[ -x "$GH" ] || GH="gh"

echo "== 1/5 Authentification GitHub =="
if ! "$GH" auth status >/dev/null 2>&1; then
  echo "→ Lancement du login (navigateur). Suis les instructions."
  "$GH" auth login --web -h github.com
fi
"$GH" auth status 2>&1 | grep -i "logged in" | head -1

echo "== 2/5 Valeurs OCI (lecture locale, jamais affichées) =="
[ -f "$CONFIG" ] || { echo "❌ $CONFIG introuvable"; exit 1; }
[ -f "$KEY" ] || { echo "❌ $KEY introuvable"; exit 1; }
OCI_USER=$(grep '^user=' "$CONFIG" | head -1 | cut -d= -f2-)
OCI_TENANCY=$(grep '^tenancy=' "$CONFIG" | head -1 | cut -d= -f2-)
OCI_FINGERPRINT=$(grep '^fingerprint=' "$CONFIG" | head -1 | cut -d= -f2-)
OCI_REGION=$(grep '^region=' "$CONFIG" | head -1 | cut -d= -f2-)
OCI_AD=$(grep '^AD=' "$SRC/orchestrate-rdp.sh" | head -1 | sed 's/^AD="//; s/"$//')
OCI_IMAGE=$(grep '^IMG=' "$SRC/orchestrate-rdp.sh" | head -1 | sed 's/^IMG=//; s/ *#.*//')
OCI_SUBNET=$(grep '^SUBNET_ID=' "$SRC/.ocid.env" | head -1 | cut -d= -f2- | tr -d '\r')
OCI_SECURITY_LIST=$(grep '^SL_ID=' "$SRC/.ocid.env" | head -1 | cut -d= -f2- | tr -d '\r')
OCI_VOLUME=$(grep '^VOLUME_ID=' "$SRC/.ocid.env" | head -1 | cut -d= -f2- | tr -d '\r')
OCI_SSH_PUB=$(cat "$SRC/ssh/oci-rdp-key.pub")
OCI_SHAPE_CONFIG=$(cat "$SRC/shape-config.json")
NTFY_TOPIC=$(cat "$HOME/.oci-rdp-ntfy-topic")

# Sanity check silencieux
[ -n "$OCI_TENANCY" ] && [ -n "$OCI_SSH_PUB" ] || { echo "❌ Extraction incomplète"; exit 1; }
echo "✓ Valeurs extraites (tenancy, image, subnet, volume, ssh, shape…)"
echo "  Topic ntfy: $NTFY_TOPIC"

echo "== 3/5 Dépôt public =="
if "$GH" repo view "$REPO" >/dev/null 2>&1; then
  echo "→ Repo $REPO existe déjà"
else
  git init -q 2>/dev/null || true
  git add -A
  git -c user.email="jarvis@growthos.local" -c user.name="JARVIS" commit -qm "feat: OCI VM retry 24/7 (GitHub Actions)"
  "$GH" repo create "$REPO" --public --description "Retry OCI VM Ampere A1 (Marseille) 24/7 — GitHub Actions, gratuit" --source . --push 2>&1 | tail -2
fi
# S'assure que le remote origin existe pour les secrets
"$GH" repo view "$REPO" >/dev/null 2>&1 || { echo "❌ Repo non créé"; exit 1; }

echo "== 4/5 GitHub Secrets =="
set_secret() { # $1=nom  $2=valeur
  local name="$1" val="$2"
  [ -n "$val" ] || { echo "  ⚠️ $name vide — SKIP"; return; }
  "$GH" secret set "$name" --repo "$REPO" --body "$val"
  echo "  ✓ $name"
}
set_secret OCI_USER "$OCI_USER"
set_secret OCI_TENANCY "$OCI_TENANCY"
set_secret OCI_FINGERPRINT "$OCI_FINGERPRINT"
set_secret OCI_API_KEY "$(cat "$KEY")"
set_secret OCI_REGION "$OCI_REGION"
set_secret OCI_AD "$OCI_AD"
set_secret OCI_IMAGE "$OCI_IMAGE"
set_secret OCI_SUBNET "$OCI_SUBNET"
set_secret OCI_SECURITY_LIST "$OCI_SECURITY_LIST"
set_secret OCI_VOLUME "$OCI_VOLUME"
set_secret OCI_SSH_PUB "$OCI_SSH_PUB"
set_secret OCI_SHAPE_CONFIG "$OCI_SHAPE_CONFIG"
set_secret NTFY_TOPIC "$NTFY_TOPIC"

echo "== 5/5 Lancement du premier run =="
if "$GH" workflow run oci-retry.yml --repo "$REPO" 2>&1; then
  echo ""
  echo "🎉 Tout est prêt ! Le retry tourne sur GitHub Actions."
  echo "→ Suivre:  gh run watch --repo $REPO"
  echo "→ Logs:    https://github.com/$(gh api user --jq .login 2>/dev/null)/$REPO/actions"
  echo "→ Abonne-toi au topic ntfy pour la notification :"
  echo "   https://ntfy.sh/$NTFY_TOPIC  (app: remplacer ntfy.sh/<topic>)"
else
  echo "⚠️ Le run n'a pas pu être lancé — vérifie les secrets puis:"
  echo "   $GH workflow run oci-retry.yml --repo $REPO"
fi
