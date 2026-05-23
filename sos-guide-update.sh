#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║         SOS-GUIDE — Mise à jour automatique du contenu JSON                ║
# ║         Source : https://sos-guide.fr/prod/                                ║
# ║         Auteur : Ludovic MARTIN — contact@sos-guide.fr                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# LOGIQUE :
#   1. Vérifie si internet est disponible via ETH (modem/téléphone)
#   2. Lit latest-version.txt sur le serveur
#   3. Compare avec la version locale installée
#   4. Si plus récente : télécharge l'archive + vérifie SHA256
#   5. Extrait uniquement les fichiers JSON dans /var/www/sos-guide/data/
#   6. Régénère le hash d'intégrité
#   7. Log le résultat
#
# SÉCURITÉ :
#   - Fonctionne UNIQUEMENT si ETH a internet (jamais depuis wlan0)
#   - Vérification SHA256 obligatoire avant toute installation
#   - Rollback automatique si l'extraction échoue
#   - Les fichiers injectés (index.html variables) ne sont PAS écrasés
#
# USAGE :
#   Manuel  : sudo bash /usr/local/bin/sos-guide-update.sh
#   Auto    : déclenché par le timer systemd (si ETH connecté)

set -e

# ── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  MAGENTA='\033[0;35m'
BOLD='\033[1m';    DIM='\033[2m';      NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✘${NC}  $1"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $1"; }
step() { echo -e "  ${BLUE}→${NC}  $1"; }

# ── Configuration ─────────────────────────────────────────────────────────────
UPDATE_URL="https://sos-guide.fr/prod"
VERSION_FILE="${UPDATE_URL}/latest-version.txt"
WEB_DIR="/var/www/sos-guide"
DATA_DIR="${WEB_DIR}/data"
VERSION_LOCAL="/root/sos-guide-content-version.txt"
INTEGRITY_HASH="/root/integrity.hash"
TMP_DIR="/tmp/sos-update-$$"
LOG_FILE="/var/log/sos-guide-update.log"
CONNECT_TIMEOUT=10
MAX_TIME=120
MODE="${1:-manual}"   # manual | auto | check

# ── Fonctions utilitaires ─────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}" 2>/dev/null || true
}

cleanup() {
    rm -rf "${TMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "Root requis : sudo bash $0"
        exit 1
    fi
}

# ── Vérifier la connectivité internet via ETH ─────────────────────────────────
check_internet() {
    step "Vérification connectivité internet (ETH)..."

    # Trouver l'interface Ethernet active avec une IP
    ETH_IFACE=$(ip -o link show | awk -F': ' '/^[0-9]+: (en|eth)/{print $2; exit}')
    if [ -z "$ETH_IFACE" ]; then
        warn "Aucune interface Ethernet détectée"
        return 1
    fi

    # Vérifier que l'interface a une adresse IP
    if ! ip -4 addr show "$ETH_IFACE" | grep -q "inet "; then
        warn "Interface $ETH_IFACE sans adresse IP — pas de connexion Internet"
        return 1
    fi

    # Test DNS + HTTP vers le serveur SOS-GUIDE
    if curl -sf \
        --connect-timeout ${CONNECT_TIMEOUT} \
        --max-time 15 \
        --interface "$ETH_IFACE" \
        -o /dev/null \
        "https://sos-guide.fr/prod/latest-version.txt" 2>/dev/null; then
        ok "Connexion internet disponible via $ETH_IFACE"
        return 0
    fi

    # Fallback : test ping DNS
    if ping -c1 -W3 -I "$ETH_IFACE" 1.1.1.1 &>/dev/null 2>&1; then
        ok "Internet disponible (ping) via $ETH_IFACE"
        return 0
    fi

    warn "Pas de connexion internet — mise à jour ignorée"
    log "SKIP: Pas de connexion internet"
    return 1
}

# ── Lire la version distante ──────────────────────────────────────────────────
fetch_remote_version() {
    REMOTE_VERSION=$(curl -sf \
        --connect-timeout ${CONNECT_TIMEOUT} \
        --max-time 15 \
        "${VERSION_FILE}" 2>/dev/null | tr -d '[:space:]')

    if [ -z "${REMOTE_VERSION}" ]; then
        warn "Impossible de lire latest-version.txt"
        log "ERROR: Impossible de lire latest-version.txt"
        return 1
    fi
    ok "Version distante : ${BOLD}${REMOTE_VERSION}${NC}"
    return 0
}

# ── Lire la version locale ────────────────────────────────────────────────────
get_local_version() {
    if [ -f "${VERSION_LOCAL}" ]; then
        LOCAL_VERSION=$(cat "${VERSION_LOCAL}" | tr -d '[:space:]')
        info "Version locale  : ${LOCAL_VERSION}"
    else
        LOCAL_VERSION="none"
        info "Version locale  : aucune (première installation)"
    fi
}

# ── Télécharger et vérifier l'archive ─────────────────────────────────────────
download_and_verify() {
    local VERSION="$1"
    local ARCHIVE_NAME="sos-guide-content-${VERSION}.tar.gz"
    local CHECKSUM_NAME="sos-guide-content-${VERSION}.sha256"
    local ARCHIVE_URL="${UPDATE_URL}/${ARCHIVE_NAME}"
    local CHECKSUM_URL="${UPDATE_URL}/${CHECKSUM_NAME}"

    mkdir -p "${TMP_DIR}"

    # Télécharger le checksum
    step "Téléchargement du checksum SHA256..."
    if ! curl -sf \
        --connect-timeout ${CONNECT_TIMEOUT} \
        --max-time 30 \
        -o "${TMP_DIR}/${CHECKSUM_NAME}" \
        "${CHECKSUM_URL}"; then
        err "Impossible de télécharger le checksum"
        log "ERROR: Échec téléchargement checksum ${CHECKSUM_URL}"
        return 1
    fi
    ok "Checksum téléchargé"

    # Télécharger l'archive avec barre de progression
    step "Téléchargement de l'archive ${ARCHIVE_NAME}..."
    if ! curl -f \
        --connect-timeout ${CONNECT_TIMEOUT} \
        --max-time ${MAX_TIME} \
        --progress-bar \
        -o "${TMP_DIR}/${ARCHIVE_NAME}" \
        "${ARCHIVE_URL}" 2>&1; then
        err "Impossible de télécharger l'archive"
        log "ERROR: Échec téléchargement ${ARCHIVE_URL}"
        return 1
    fi
    echo ""
    ok "Archive téléchargée"

    # Vérification SHA256
    step "Vérification SHA256..."
    cd "${TMP_DIR}"

    # Le fichier .sha256 peut contenir : "HASH  filename" ou juste "HASH"
    EXPECTED_HASH=$(awk '{print $1}' "${CHECKSUM_NAME}")
    ACTUAL_HASH=$(sha256sum "${ARCHIVE_NAME}" | awk '{print $1}')

    if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
        err "SHA256 invalide ! Archive corrompue ou attaque."
        err "  Attendu : ${EXPECTED_HASH}"
        err "  Obtenu  : ${ACTUAL_HASH}"
        log "SECURITY: SHA256 invalide pour ${ARCHIVE_NAME}"
        return 1
    fi
    ok "SHA256 vérifié ✓"
    cd - >/dev/null

    ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"
    return 0
}

# ── Vérifier le contenu de l'archive avant extraction ─────────────────────────
verify_archive_content() {
    local ARCHIVE="$1"
    step "Vérification du contenu de l'archive..."

    # Lister les fichiers — vérifier qu'il n'y a que des JSON dans data/
    local BAD_FILES
    BAD_FILES=$(tar -tzf "${ARCHIVE}" 2>/dev/null | grep -v '\.json$' | grep -v '/$' || true)

    if [ -n "${BAD_FILES}" ]; then
        warn "Fichiers non-JSON détectés dans l'archive :"
        echo "${BAD_FILES}" | head -5 | while read -r f; do warn "  ${f}"; done
        err "Archive rejetée : seuls les fichiers .json sont autorisés"
        log "SECURITY: Archive contient des fichiers non-JSON"
        return 1
    fi

    local FILE_COUNT
    FILE_COUNT=$(tar -tzf "${ARCHIVE}" 2>/dev/null | grep '\.json$' | wc -l)
    ok "Archive valide : ${FILE_COUNT} fichier(s) JSON"
    return 0
}

# ── Installer le contenu ───────────────────────────────────────────────────────
install_content() {
    local ARCHIVE="$1"
    local VERSION="$2"

    # Sauvegarde de la version actuelle
    if [ -d "${DATA_DIR}" ]; then
        step "Sauvegarde de la version actuelle..."
        cp -r "${DATA_DIR}" "${TMP_DIR}/data_backup" 2>/dev/null || true
        ok "Sauvegarde créée dans ${TMP_DIR}/data_backup"
    fi

    # Déverrouillage
    step "Déverrouillage du répertoire web..."
    chattr -R -i "${WEB_DIR}/" 2>/dev/null || true
    chmod -R u+w "${WEB_DIR}/"

    # Extraction dans un dossier temporaire d'abord
    step "Extraction de l'archive..."
    mkdir -p "${TMP_DIR}/extract"
    if ! tar -xzf "${ARCHIVE}" -C "${TMP_DIR}/extract" 2>/dev/null; then
        err "Échec extraction — rollback..."
        # Rollback
        if [ -d "${TMP_DIR}/data_backup" ]; then
            rm -rf "${DATA_DIR}"
            cp -r "${TMP_DIR}/data_backup" "${DATA_DIR}"
            warn "Rollback effectué — ancienne version restaurée"
        fi
        chattr -R +i "${WEB_DIR}/" 2>/dev/null || true
        return 1
    fi
    ok "Extraction réussie"

    # Copie des JSON vers /var/www/sos-guide/data/
    step "Installation des fichiers JSON..."
    # L'archive peut avoir une structure data/fr/*.json ou directement fr/*.json
    if [ -d "${TMP_DIR}/extract/data" ]; then
        # Structure : data/fr/*.json
        cp -r "${TMP_DIR}/extract/data/"* "${DATA_DIR}/"
    elif [ -d "${TMP_DIR}/extract/fr" ]; then
        # Structure : fr/*.json
        mkdir -p "${DATA_DIR}"
        cp -r "${TMP_DIR}/extract/"* "${DATA_DIR}/"
    else
        # Structure plate : *.json → on cherche les dossiers de langue
        find "${TMP_DIR}/extract" -name "*.json" -exec cp {} "${DATA_DIR}/" \;
    fi

    chown -R www-data:www-data "${DATA_DIR}"
    chmod -R 755 "${DATA_DIR}"
    find "${DATA_DIR}" -name "*.json" -exec chmod 644 {} \;
    ok "Fichiers JSON installés dans ${DATA_DIR}"

    # Sauvegarder la nouvelle version
    echo "${VERSION}" > "${VERSION_LOCAL}"
    ok "Version locale mise à jour : ${VERSION}"

    # Reverrouillage
    step "Reverrouillage..."
    chmod -R a-w "${WEB_DIR}/"
    chattr -R +i "${WEB_DIR}/" 2>/dev/null || true

    # Régénération du hash d'intégrité
    step "Régénération du hash SHA256 d'intégrité..."
    find "${WEB_DIR}" -type f -exec sha256sum {} \; > "${INTEGRITY_HASH}" 2>/dev/null
    sha256sum /etc/nginx/sites-available/sos-guide >> "${INTEGRITY_HASH}" 2>/dev/null || true
    ok "Hash d'intégrité régénéré"

    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# PROGRAMME PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════

check_root

# Mode "check only" — juste vérifier si une mise à jour est disponible
if [ "${MODE}" = "check" ]; then
    check_internet || exit 0
    fetch_remote_version || exit 0
    get_local_version
    if [ "${REMOTE_VERSION}" != "${LOCAL_VERSION}" ]; then
        echo -e "${YELLOW}Mise à jour disponible : ${LOCAL_VERSION} → ${REMOTE_VERSION}${NC}"
        echo -e "${CYAN}Lancer : sudo bash /usr/local/bin/sos-guide-update.sh${NC}"
        exit 2  # code 2 = update disponible
    else
        echo -e "${GREEN}Contenu à jour : ${LOCAL_VERSION}${NC}"
        exit 0
    fi
fi

# Mode "auto" — silencieux si pas de mise à jour
if [ "${MODE}" = "auto" ]; then
    # Log minimal
    exec >> "${LOG_FILE}" 2>&1
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  SOS-GUIDE Update — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════"
fi

echo ""
echo -e "${BOLD}${CYAN}  ⛑️  SOS-GUIDE — Mise à jour du contenu${NC}"
echo -e "${DIM}  Source : ${UPDATE_URL}${NC}"
echo ""

# 1. Vérifier internet
check_internet || exit 0

# 2. Lire les versions
fetch_remote_version || exit 1
get_local_version

# 3. Comparer
if [ "${REMOTE_VERSION}" = "${LOCAL_VERSION}" ]; then
    ok "Contenu déjà à jour (${LOCAL_VERSION})"
    log "OK: Contenu à jour ${LOCAL_VERSION}"
    echo ""
    exit 0
fi

echo ""
echo -e "  ${BOLD}${MAGENTA}Mise à jour disponible :${NC}"
echo -e "  ${DIM}${LOCAL_VERSION}${NC} → ${BOLD}${GREEN}${REMOTE_VERSION}${NC}"
echo ""

# En mode manuel, demander confirmation
if [ "${MODE}" = "manual" ]; then
    read -p "  Installer la mise à jour ? (o/N) : " CONFIRM
    if [ "${CONFIRM}" != "o" ] && [ "${CONFIRM}" != "O" ]; then
        info "Mise à jour annulée"
        exit 0
    fi
fi

echo ""

# 4. Télécharger et vérifier
download_and_verify "${REMOTE_VERSION}" || exit 1

# 5. Vérifier le contenu de l'archive
verify_archive_content "${ARCHIVE_PATH}" || exit 1

# 6. Installer
install_content "${ARCHIVE_PATH}" "${REMOTE_VERSION}" || exit 1

echo ""
echo -e "  ${GREEN}${BOLD}✔  Mise à jour ${REMOTE_VERSION} installée avec succès !${NC}"
log "SUCCESS: Mise à jour ${LOCAL_VERSION} → ${REMOTE_VERSION}"

if [ "${MODE}" = "auto" ]; then
    logger "SOS-GUIDE: Contenu mis à jour ${LOCAL_VERSION} → ${REMOTE_VERSION}"
fi

echo ""
exit 0
