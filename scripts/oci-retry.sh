#!/usr/bin/env bash
# ============================================================
# RETRY OCI VM — Ampere A1 (Marseille), Always Free.
# Tourne sur GitHub Actions (dépôt public), gratuit et continu.
# Tente la création toutes les 30s jusqu'à succès, puis notifie
# via ntfy.sh. Se re-déclenche via le workflow (oci-retry.yml).
#
# ⚠️ DÉPÔT PUBLIC : ne JAMAIS echo/print un secret (clé API, OCIDs).
# Toutes les valeurs viennent des env du workflow (GitHub Secrets).
# ============================================================
set -u

# ── 1. Clé API privée → fichier temporaire (600) ─────────────
KEYFILE="/tmp/oci_api_key.pem"
mkdir -p /tmp
printf '%s\n' "$OCI_API_KEY" > "$KEYFILE"
chmod 600 "$KEYFILE"

# Clé SSH publique → fichier temporaire (c'est une clé publique).
SSHFILE="/tmp/oci_ssh_pub.pub"
printf '%s\n' "$OCI_SSH_PUB" > "$SSHFILE"

# ── 2. Configure le CLI OCI via variables d'env (jamais de fichier) ──
export OCI_CLI_USER="$OCI_USER"
export OCI_CLI_TENANCY="$OCI_TENANCY"
export OCI_CLI_FINGERPRINT="$OCI_FINGERPRINT"
export OCI_CLI_KEY_FILE="$KEYFILE"
export OCI_CLI_REGION="$OCI_REGION"

OCI="oci"
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ── 3. Notification ntfy — URL COMPLÈTE obligatoire + échec tracé ──
# 🔴 BUG FIX (2026-08-13) : le secret NTFY_TOPIC = NOM du topic seul
# (ex: oci-rdp-xxx), pas une URL. `curl -d ... "$NTFY_TOPIC"` échouait
# SILENCIEUSEMENT (protocol invalide, masqué par >/dev/null || true) →
# la VM a été créée le 12/08 19:59 UTC sans AUCUNE notification.
# Fix : construire https://ntfy.sh/<topic> + logguer le code HTTP.
NTFY_URL="https://ntfy.sh/${NTFY_TOPIC:-}"
notify(){
  local msg="$1"
  local code
  [ -n "$NTFY_URL" ] || { log "   ⚠️ ntfy NON CONFIGURÉ (NTFY_TOPIC vide)"; return 0; }
  code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -d "$msg" "$NTFY_URL" 2>/dev/null)
  case "$code" in
    200) log "   ✔ ntfy OK (200)" ;;
    *)   log "   ⚠️ ntfy ÉCHEC (HTTP '${code:-réseau}') — notification non reçue : $msg" ;;
  esac
}

# ── 4. VM déjà créée ? → notification (UNE SEULE FOIS) + arrêt ──
# Anti-spam : le flag repo VM_NOTIFIED empêche de renvoyer la notif
# "déjà créée" à chaque run schedule (4×/jour sinon). On ne le pose
# qu'après un envoi ntfy réussi (retry au run suivant si échec).
if "$OCI" compute instance list --compartment-id "$OCI_TENANCY" --all 2>/dev/null | grep -q 'rdp-main'; then
  log "VM rdp-main existe déjà — rien à faire."
  if gh secret list --repo "$GITHUB_REPOSITORY" 2>/dev/null | grep -q '^VM_NOTIFIED'; then
    log "   (déjà notifié — flag VM_NOTIFIED présent, pas de spam)"
  else
    notify "VM Oracle RDP déjà créée ✅ (IP: 129.151.228.78 — voir Oracle-RDP.rdp)"
    gh secret set VM_NOTIFIED --repo "$GITHUB_REPOSITORY" --body "true" 2>/dev/null || log "   ⚠️ flag VM_NOTIFIED non posé (retenté au prochain run)"
  fi
  exit 0
fi

# ── 5. Boucle de retry 30s ─────────────────────────────────────
TRIES=0
while true; do
  TRIES=$((TRIES + 1))
  log "Tentative $TRIES ..."

  # timeout 120 : la réponse OCI met souvent 90-120s quand la région est chargée
  # (observé : "Too many requests" à ~97s). timeout 25 coupait TOUTES les réponses
  # avant qu'elles n'arrivent → on voyait "timeout 25s (OCI lent)" au lieu du vrai
  # message OCI. 120s > max observé → on reçoit la vraie réponse (capacity, too many…).
  # Cadence réelle : tentative + réponse (~100s) + sleep 30 = ~130-150s.
  OUT=$(timeout 120 "$OCI" compute instance launch \
    --compartment-id "$OCI_TENANCY" \
    --availability-domain "$OCI_AD" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "$OCI_SHAPE_CONFIG" \
    --image-id "$OCI_IMAGE" \
    --subnet-id "$OCI_SUBNET" \
    --assign-public-ip true \
    --display-name "rdp-main" \
    --ssh-authorized-keys-file "$SSHFILE" \
    --boot-volume-size-in-gbs 100 2>&1)
  RC=$?

  VMID=$(echo "$OUT" | grep -o 'ocid1.instance[^"]*' | head -1)
  if [ -n "$VMID" ]; then
    log "✅✅ VM CREEE: $VMID"
    notify "VM Oracle RDP créée ! OCID: $VMID — l'IP arrive, config en cours."
    exit 0
  fi

  if [ "$RC" -eq 124 ]; then
    # timeout 120 atteint : la réponse OCI a mis >120s (très chargé). On log la
    # sortie partielle si présente (une VM peut avoir été créée malgré le timeout).
    PARTIAL=$(echo "$OUT" | grep -o 'ocid1.instance[^"]*' | head -1)
    if [ -n "$PARTIAL" ]; then
      log "   -> ⚠️ timeout 120s MAIS instance créée: $PARTIAL — vérifier, la notification est partie"
      notify "⚠️ timeout OCI MAIS instance créée: $PARTIAL — vérifier sur OCI"
      exit 0
    fi
    log "   -> timeout 120s (aucune réponse OCI en 120s — tentative suivante dans 30s)"
  else
    MSG=$(echo "$OUT" | grep -o '"message": "[^"]*"' | head -1 | cut -d'"' -f4)
    log "   -> ${MSG:-échec inconnu (rc=$RC)}"
    # Trace de debug : la sortie OCI brute (sans secrets — OCIDs = identifiants publics, pas des secrets)
    [ -n "$OUT" ] && [ "$RC" -ne 124 ] && echo "$OUT" | grep -o '"code": "[^"]*"\|"message": "[^"]*"' | head -2 | sed 's/^/       /' | while read -r l; do log "$l"; done
  fi
  sleep 30
done
