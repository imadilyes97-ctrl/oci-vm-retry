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

# ── 3. VM déjà créée ? → notification + arrêt (pas de re-déclenchement) ──
if "$OCI" compute instance list --compartment-id "$OCI_TENANCY" --all 2>/dev/null | grep -q 'rdp-main'; then
  log "VM rdp-main existe déjà — rien à faire."
  curl -s -d "VM Oracle RDP déjà créée ✅ (connexion: voir Oracle-RDP.rdp)" "$NTFY_TOPIC" >/dev/null 2>&1 || true
  exit 0
fi

# ── 4. Boucle de retry 30s ─────────────────────────────────────
TRIES=0
while true; do
  TRIES=$((TRIES + 1))
  log "Tentative $TRIES ..."

  # timeout 25 : borne la durée de l'appel OCI (qui peut traîner 300s+ quand la
  # région est chargée). Si OCI ne répond pas en 25s → on passe à la tentative
  # suivante dans 30s → cadence RÉELLE bornée à ~55s max (jamais 2-5 min).
  OUT=$(timeout 25 "$OCI" compute instance launch \
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

  VMID=$(echo "$OUT" | grep -o 'ocid1.instance[^"]*' | head -1)
  if [ -n "$VMID" ]; then
    log "✅✅ VM CREEE: $VMID"
    curl -s -d "VM Oracle RDP créée ! OCID: $VMID — l'IP arrive, config en cours." "$NTFY_TOPIC" >/dev/null 2>&1 || true
    exit 0
  fi

  MSG=$(echo "$OUT" | grep -o '"message": "[^"]*"' | head -1 | cut -d'"' -f4)
  log "   -> ${MSG:-échec inconnu}"
  sleep 30
done
