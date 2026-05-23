#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║           ⛑️  SOS-GUIDE v2.1 — Emergency Offline Survival System           ║
# ║                  Raspberry Pi OS Trixie — Production                        ║
# ║           Auteur : Ludovic MARTIN — contact@sos-guide.fr                   ║
# ║           Version CORRIGÉE — Avril 2026                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# COULEURS & STYLES
# ══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';    MAGENTA='\033[0;35m'
WHITE='\033[1;37m';  GRAY='\033[0;37m';    NC='\033[0m'
BOLD='\033[1m';      DIM='\033[2m';        UNDER='\033[4m'

# ══════════════════════════════════════════════════════════════════════════════
# FONCTIONS UI
# ══════════════════════════════════════════════════════════════════════════════
sep() { echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"; }
sep_bold() { echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"; }
section() { echo ""; sep_bold; echo -e "  ${BOLD}${CYAN}$1${NC}"; sep_bold; echo ""; }
subsection() { echo ""; echo -e "  ${BOLD}${WHITE}▶ $1${NC}"; sep; }
ok()   { echo -e "  ${GREEN}✔${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✘${NC}  $1"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $1"; }
step() { echo -e "  ${BLUE}→${NC}  $1"; }

# Barre de progression simplifiée sans animation risquée
progress() {
    local MSG="$1"
    local WIDTH=50
    printf "  ${CYAN}%-36s${NC} [" "${MSG}"
    printf "${GREEN}█%.0s${NC}" $(seq 1 $WIDTH)
    printf "] ${GREEN}✔${NC}\n"
}

# Spinner amélioré avec wait
spinner() {
    local PID=$1
    local MSG="$2"
    local FRAMES=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 $PID 2>/dev/null; do
        printf "\r  ${CYAN}${FRAMES[$i]}${NC}  ${MSG}"
        i=$(( (i+1) % 8 ))
        sleep 0.1
    done
    wait $PID  # attend la fin réelle du processus
    tput cnorm 2>/dev/null || true
    printf "\r  ${GREEN}✔${NC}  ${MSG}\n"
}

STEP_NUM=0
STEP_TOTAL=18

next_step() {
    STEP_NUM=$((STEP_NUM + 1))
    local LABEL="$1"
    echo ""
    echo -e "  ${BOLD}${MAGENTA}[${STEP_NUM}/${STEP_TOTAL}]${NC} ${BOLD}${WHITE}${LABEL}${NC}"
    sep
}

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION GLOBALE
# ══════════════════════════════════════════════════════════════════════════════
SSID="⛑️ SOS-GUIDE"
LOCAL_IP="10.0.0.1"
WIFI_IFACE=""
ETH_IFACE=""
HOSTNAME_SET="sos-guide"
ETH_MODE_ONLY=false

# Fonctions de détection robuste des interfaces
detect_wifi_iface() {
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        if iw dev "$iface" info >/dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

detect_eth_iface() {
    # Priorité aux interfaces nommées eth* ou en*
    local iface=$(ip -o link show | awk -F': ' '/^[0-9]+: (en|eth)/ {print $2; exit}')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi
    # Fallback: première interface non-wifi et non lo
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        if [ "$iface" != "lo" ] && [ ! -d "/sys/class/net/$iface/wireless" ]; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

WIFI_IFACE=$(detect_wifi_iface || true)
if [ -z "$WIFI_IFACE" ]; then
    err "Aucune interface WiFi détectée"
    echo -e "  ${CYAN}  → WIFI_IFACE=wlan0 sudo bash install.sh${NC}"
    exit 1
fi
ok "Interface WiFi : ${BOLD}${WIFI_IFACE}${NC}"

ETH_IFACE=$(detect_eth_iface || true)
if [ -z "$ETH_IFACE" ]; then
    warn "Interface Ethernet non détectée — mode WiFi uniquement"
    ETH_IFACE="eth0"
    ETH_MODE_ONLY=true
else
    ok "Interface Ethernet : ${BOLD}${ETH_IFACE}${NC}"
fi

# Variables lieu
LOC_NAME="Lieu Non Défini"
LOC_ADDRESS="Adresse non renseignée"
LOC_LAT=""
LOC_LON=""
ESTABLISHMENT_TYPE="erp"
LOCAL_CRISIS_NUMBER=""
LOCAL_RISK=""
LOCAL_SAMU_NUMBER=""
LOCAL_POMPIERS_NUMBER=""
LOCAL_MAIRIE_NUMBER=""
LOCAL_PREFECTURE=""
LOCAL_DSDEN=""
LOCAL_RADIO_FREQ=""
LOCAL_CROIX_ROUGE=""
LOCAL_PCC_ADDRESS=""
LOCAL_MEETING_POINT=""
LOCAL_EVACUATION_PLAN=""
COPY_CUSTOM_IMAGE=false
CUSTOM_IMAGE_SOURCE="/home/pi/map_location.png"
REASSURANCE_MESSAGE="Restez calme, les secours sont informés et arrivent."

# ══════════════════════════════════════════════════════════════════════════════
# BANNIÈRE D'ACCUEIL
# ══════════════════════════════════════════════════════════════════════════════
clear
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════════════════╗"
echo "  ║                                                                      ║"
echo "  ║        ⛑️   S O S - G U I D E   v 2 . 1   P R O D U C T I O N        ║"
echo "  ║                                                                      ║"
echo "  ║          Emergency Offline Survival System — Raspberry Pi            ║"
echo "  ║                                                                      ║"
echo "  ╚══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Auteur   : Ludovic MARTIN${NC}"
echo -e "  ${DIM}Contact  : contact@sos-guide.fr${NC}"
echo -e "  ${DIM}Licence  : MIT — github.com/sos-guide${NC}"
echo ""
sep_bold
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# VÉRIFICATIONS PRÉALABLES
# ══════════════════════════════════════════════════════════════════════════════
subsection "Vérifications préalables"
if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être exécuté en root"
    echo -e "  ${CYAN}  → sudo bash install.sh${NC}"
    exit 1
fi
ok "Exécution en root"

# Vérifier que nous sommes dans le bon répertoire (contient web/ etc.)
if [ ! -d "web" ] || [ ! -d "firstboot" ]; then
    err "Le script doit être exécuté depuis la racine du dépôt SOS-GUIDE"
    echo -e "  ${CYAN}  → cd sos-guide && sudo bash install.sh${NC}"
    exit 1
fi
ok "Structure du dépôt détectée"

echo ""
info "Démarrage de l'installation dans 3 secondes..."
sleep 3

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — NETTOYAGE
# ══════════════════════════════════════════════════════════════════════════════
next_step "Nettoyage des services conflictuels"
for svc in bluetooth NetworkManager wpa_supplicant avahi-daemon avahi-daemon.socket ModemManager dhcpcd; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    systemctl mask "$svc" 2>/dev/null || true
done
pkill -f wpa_supplicant 2>/dev/null || true
pkill -f NetworkManager 2>/dev/null || true
systemctl disable getty@tty2.service 2>/dev/null || true
systemctl disable getty@tty3.service 2>/dev/null || true
echo 0 > /proc/sys/kernel/sysrq
progress "Nettoyage services réseau"
ok "Services conflictuels désactivés"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — NTP
# ══════════════════════════════════════════════════════════════════════════════
next_step "Synchronisation NTP"
cat > /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org
RootDistanceMaxSec=30
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
systemctl enable systemd-timesyncd >/dev/null 2>&1
systemctl restart systemd-timesyncd >/dev/null 2>&1
timedatectl set-ntp true >/dev/null 2>&1
step "Attente synchronisation NTP (max 60s)..."
for i in $(seq 1 12); do
    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
        ok "Heure synchronisée"
        break
    fi
    printf "  ${DIM}.${NC}"
    sleep 5
done
echo ""
info "Date : $(date '+%A %d/%m/%Y %H:%M:%S')"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — PAQUETS
# ══════════════════════════════════════════════════════════════════════════════
next_step "Installation des paquets système"
step "Mise à jour des dépôts..."
apt update -qq 2>/dev/null &
spinner $! "apt update"

step "Mise à niveau du système..."
apt dist-upgrade -y -qq 2>/dev/null &
spinner $! "apt dist-upgrade"

step "Installation des paquets SOS-GUIDE..."
apt install -y -qq nginx hostapd dnsmasq iptables-persistent netfilter-persistent \
    systemd-resolved watchdog e2fsprogs curl dnsutils openssl iw \
    php-fpm apache2-utils jq 2>/dev/null &
spinner $! "nginx hostapd dnsmasq watchdog iw php-fpm apache2-utils jq curl dnsutils..."
ok "Tous les paquets installés"

# Déterminer la version de PHP installée
PHP_VERSION=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
if [ -z "$PHP_VERSION" ]; then
    PHP_VERSION="8.2"
fi
ok "PHP version détectée : $PHP_VERSION"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3.5 — CONFIGURATION DU LIEU ET DES CONTACTS
# ══════════════════════════════════════════════════════════════════════════════
section "🏢  CONFIGURATION DU LIEU ET DES CONTACTS"
subsection "Informations du lieu"
echo -e "  ${DIM}Ces informations s'affichent sur le portail captif${NC}"
echo ""
read -p "  🏢  Nom du lieu (ex: Mairie de Paris) : " LOC_NAME
[ -z "${LOC_NAME}" ] && LOC_NAME="Lieu Non Défini"
ok "Nom : ${LOC_NAME}"

read -p "  📍  Adresse complète : " LOC_ADDRESS
[ -z "${LOC_ADDRESS}" ] && LOC_ADDRESS="Adresse non renseignée"
ok "Adresse : ${LOC_ADDRESS}"

echo ""
info "Coordonnées GPS (optionnel) — pour la carte PNG zoomable"
read -p "  🌐  Latitude  (ex: 48.8566) : " LOC_LAT
read -p "  🌐  Longitude (ex: 2.3522)  : " LOC_LON
if [ -n "${LOC_LAT}" ] && [ -n "${LOC_LON}" ]; then
    ok "Coordonnées GPS : ${LOC_LAT}, ${LOC_LON}"
else
    warn "Coordonnées manquantes — carte désactivée"
fi

subsection "Type d'établissement"
echo ""
echo -e "  ${CYAN}1${NC}  erp         — Établissement recevant du public ${DIM}(défaut)${NC}"
echo -e "  ${CYAN}2${NC}  ecole       — École, collège, lycée"
echo -e "  ${CYAN}3${NC}  mairie      — Mairie, hôtel de ville"
echo -e "  ${CYAN}4${NC}  ehpad       — Maison de retraite, EHPAD"
echo -e "  ${CYAN}5${NC}  entreprise  — Bureau, usine, entrepôt"
echo -e "  ${CYAN}6${NC}  bar         — Bar, restaurant, café"
echo -e "  ${CYAN}7${NC}  boitedenuit — Discothèque, salle de concert"
echo -e "  ${CYAN}8${NC}  hopital     — Hôpital, clinique, centre médical"
echo -e "  ${CYAN}9${NC}  gymnase     — Gymnase, salle polyvalente, point de rassemblement"
echo ""
read -p "  → Choix (1-9) : " type_choice
case "$type_choice" in
    1) ESTABLISHMENT_TYPE="erp" ;;
    2) ESTABLISHMENT_TYPE="ecole" ;;
    3) ESTABLISHMENT_TYPE="mairie" ;;
    4) ESTABLISHMENT_TYPE="ehpad" ;;
    5) ESTABLISHMENT_TYPE="entreprise" ;;
    6) ESTABLISHMENT_TYPE="bar" ;;
    7) ESTABLISHMENT_TYPE="boitedenuit" ;;
    8) ESTABLISHMENT_TYPE="hopital" ;;
    9) ESTABLISHMENT_TYPE="gymnase" ;;
    *) ESTABLISHMENT_TYPE="erp" ;;
esac
ok "Type d'établissement : ${BOLD}${ESTABLISHMENT_TYPE}${NC}"

subsection "Contacts locaux d'urgence"
echo -e "  ${DIM}Appuyez sur Entrée pour ignorer un champ optionnel${NC}"
echo ""
read -p "  📞  Numéro cellule de crise locale      : " LOCAL_CRISIS_NUMBER
[ -n "${LOCAL_CRISIS_NUMBER}" ] && ok "Crise locale : ${LOCAL_CRISIS_NUMBER}" || warn "Crise locale : non renseigné"

read -p "  🚑  SAMU local                (optionnel) : " LOCAL_SAMU_NUMBER
[ -n "${LOCAL_SAMU_NUMBER}" ] && ok "SAMU local : ${LOCAL_SAMU_NUMBER}"

read -p "  🚒  Caserne pompiers locale   (optionnel) : " LOCAL_POMPIERS_NUMBER
[ -n "${LOCAL_POMPIERS_NUMBER}" ] && ok "Pompiers : ${LOCAL_POMPIERS_NUMBER}"

read -p "  🏛️  Mairie / Contact municipal (optionnel) : " LOCAL_MAIRIE_NUMBER
[ -n "${LOCAL_MAIRIE_NUMBER}" ] && ok "Mairie : ${LOCAL_MAIRIE_NUMBER}"

read -p "  🏛️  Préfecture               (optionnel) : " LOCAL_PREFECTURE
[ -n "${LOCAL_PREFECTURE}" ] && ok "Préfecture : ${LOCAL_PREFECTURE}"

if [ "${ESTABLISHMENT_TYPE}" = "ecole" ]; then
    read -p "  🎓  DSDEN                     (optionnel) : " LOCAL_DSDEN
    [ -n "${LOCAL_DSDEN}" ] && ok "DSDEN : ${LOCAL_DSDEN}"
fi

read -p "  📻  Fréquence radio locale MHz (optionnel) : " LOCAL_RADIO_FREQ
[ -n "${LOCAL_RADIO_FREQ}" ] && ok "Radio locale : ${LOCAL_RADIO_FREQ} MHz"

read -p "  🔴  Croix-Rouge locale        (optionnel) : " LOCAL_CROIX_ROUGE
[ -n "${LOCAL_CROIX_ROUGE}" ] && ok "Croix-Rouge : ${LOCAL_CROIX_ROUGE}"

read -p "  📍  Adresse PCC               (optionnel) : " LOCAL_PCC_ADDRESS
[ -n "${LOCAL_PCC_ADDRESS}" ] && ok "PCC : ${LOCAL_PCC_ADDRESS}"

read -p "  🚶  Point de rassemblement    (optionnel) : " LOCAL_MEETING_POINT
[ -n "${LOCAL_MEETING_POINT}" ] && ok "Rassemblement : ${LOCAL_MEETING_POINT}"

read -p "  🗺️  Plan d'évacuation         (optionnel) : " LOCAL_EVACUATION_PLAN
[ -n "${LOCAL_EVACUATION_PLAN}" ] && ok "Évacuation : ${LOCAL_EVACUATION_PLAN}"

read -p "  ⚠️  Risque local spécifique   (optionnel) : " LOCAL_RISK
[ -n "${LOCAL_RISK}" ] && ok "Risque : ${LOCAL_RISK}" || warn "Risque : non précisé"

# Message de réassurance
read -p "  🕊️  Message de réassurance (ex: 'Restez calme...') : " REASSURANCE_MESSAGE
[ -z "$REASSURANCE_MESSAGE" ] && REASSURANCE_MESSAGE="Restez calme, les secours sont informés et arrivent."
ok "Message de réassurance défini"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3.6 — IMAGE CARTE PNG
# ══════════════════════════════════════════════════════════════════════════════
next_step "Carte PNG personnalisée"
read -p "  🖼️  Chemin vers l'image PNG (laisser vide si aucune) : " custom_path
if [ -n "$custom_path" ]; then
    CUSTOM_IMAGE_SOURCE="$custom_path"
fi
if [ -f "${CUSTOM_IMAGE_SOURCE}" ]; then
    ok "Carte trouvée : ${CUSTOM_IMAGE_SOURCE}"
    COPY_CUSTOM_IMAGE=true
else
    warn "Carte introuvable : ${CUSTOM_IMAGE_SOURCE}"
    info "Copiez-la plus tard : cp /home/pi/map_location.png /var/www/sos-guide/img/"
    COPY_CUSTOM_IMAGE=false
fi

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — PAYS WIFI
# ══════════════════════════════════════════════════════════════════════════════
next_step "Configuration du pays WiFi"
rfkill unblock wifi 2>/dev/null || true
iw reg set FR 2>/dev/null || { err "Échec iw reg set FR — iw peut-être manquant"; exit 1; }
progress "Réglementation WiFi FR (canal 11, 100mW)"
ok "Pays WiFi configuré : France"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — RÉSEAU
# ══════════════════════════════════════════════════════════════════════════════
next_step "Configuration systemd-networkd"
systemctl unmask systemd-networkd 2>/dev/null || true
systemctl enable systemd-networkd >/dev/null 2>&1

if [ "${ETH_MODE_ONLY}" = false ]; then
    ETH_NET_FILE="10-${ETH_IFACE}.network"
    cat > /etc/systemd/network/${ETH_NET_FILE} <<EOF
[Match]
Name=${ETH_IFACE}

[Network]
DHCP=yes
IPv6AcceptRA=no
IPv6DHCP=no
DNS=1.1.1.1
DNS=8.8.4.4

[DHCP]
RouteMetric=10
EOF
    ok "ETH ${ETH_IFACE} : DHCP configuré"
    info "IP dynamique via modem → accès SSH via l'IP DHCP (ip a show eth0)"
else
    warn "Mode WiFi seul — ETH ignoré"
fi

cat > /etc/systemd/network/20-wlan-ap.network <<EOF
[Match]
Name=${WIFI_IFACE}

[Network]
Address=${LOCAL_IP}/24
IPv6AcceptRA=no
IPv6LinkLocalAddressGenerationMode=none
IPv6Token=none
IPv6Disable=1

[Link]
WakeOnLan=off

[WLAN]
PowerSave=off
EOF
ok "WiFi ${WIFI_IFACE} : IP ${LOCAL_IP}/24 configurée"

systemctl daemon-reload >/dev/null 2>&1
systemctl restart systemd-networkd >/dev/null 2>&1 &
spinner $! "Redémarrage systemd-networkd"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — DNS
# ══════════════════════════════════════════════════════════════════════════════
next_step "Configuration DNS"
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf <<EOF
[Resolve]
DNS=1.1.1.1 8.8.4.4
FallbackDNS=
DNSStubListener=no
DNSOverTLS=no
LLMNR=no
MulticastDNS=no
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl restart systemd-resolved >/dev/null 2>&1
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
ok "systemd-resolved configuré"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 7 — HOSTAPD
# ══════════════════════════════════════════════════════════════════════════════
next_step "Point d'accès WiFi (hostapd)"
TS=$(date +%Y%m%d_%H%M%S)
[ -d /etc/hostapd ] && cp -a /etc/hostapd /etc/hostapd.bak.$TS 2>/dev/null || true
mkdir -p /etc/hostapd

cat > /etc/hostapd/hostapd.conf <<EOF
interface=${WIFI_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=11
wmm_enabled=1
beacon_int=100
dtim_period=1
max_num_sta=50
country_code=FR
ap_isolate=1
ieee80211d=1
ieee80211n=1
auth_algs=1
wpa=0
ignore_broadcast_ssid=0
EOF

if [ ! -s /etc/hostapd/hostapd.conf ]; then
    err "Le fichier /etc/hostapd/hostapd.conf est vide !"
    exit 1
fi
ok "Fichier hostapd.conf créé"

cat > /etc/default/hostapd <<EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
DAEMON_OPTS=""
EOF

ip link set ${WIFI_IFACE} down 2>/dev/null || true
sleep 1
systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd >/dev/null 2>&1
systemctl restart hostapd
sleep 2

if systemctl is-active --quiet hostapd; then
    ok "hostapd démarré avec succès"
else
    err "hostapd n'a pas démarré. Voir logs : journalctl -u hostapd"
    exit 1
fi

if iw dev ${WIFI_IFACE} info 2>/dev/null | grep -q "type AP"; then
    ok "Interface ${WIFI_IFACE} en mode AP"
else
    warn "L'interface ${WIFI_IFACE} n'est pas en mode AP (peut prendre quelques secondes)"
fi

ok "SSID : ${BOLD}${SSID}${NC}"
ok "Canal 11 — Réseau ouvert — ap_isolate=1"
ok "Capacité : 50 clients simultanés"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 8 — DNSMASQ
# ══════════════════════════════════════════════════════════════════════════════
next_step "Portail captif dnsmasq"
[ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak.$TS 2>/dev/null || true

cat > /etc/dnsmasq.conf <<EOF
bind-dynamic
interface=${WIFI_IFACE}
listen-address=${LOCAL_IP}
dhcp-authoritative
dhcp-range=${LOCAL_IP%.*}.100,${LOCAL_IP%.*}.200,1h
dhcp-option=3,${LOCAL_IP}
dhcp-option=6,${LOCAL_IP}
dhcp-option=114,"http://${LOCAL_IP}/"
address=/sos.guide/${LOCAL_IP}
address=/#/${LOCAL_IP}
no-resolv
no-hosts
cache-size=0
EOF

systemctl enable dnsmasq >/dev/null 2>&1
systemctl restart dnsmasq
sleep 2

if systemctl is-active --quiet dnsmasq; then
    ok "dnsmasq démarré"
else
    err "dnsmasq n'a pas démarré"
    exit 1
fi

ok "DHCP : ${LOCAL_IP%.*}.100 → .200"
ok "DNS wildcard → ${LOCAL_IP} (spoofing OK)"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 9 — FIREWALL iptables
# ══════════════════════════════════════════════════════════════════════════════
next_step "Firewall iptables — Isolation totale + DNS forcé"

# Nettoyage
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Politiques par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Protection de base
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# SSH uniquement sur ETH (accès admin sécurisé)
if [ "${ETH_MODE_ONLY}" = false ]; then
    iptables -A INPUT -i ${ETH_IFACE} -p tcp --dport 22 -m conntrack --ctstate NEW \
        -m limit --limit 3/min --limit-burst 3 -j ACCEPT
    ok "SSH autorisé sur ${ETH_IFACE} (3 conn/min max)"
fi

# Limitation des requêtes HTTP/HTTPS (protection DDoS légère)
iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 80 \
    -m limit --limit 30/second --limit-burst 200 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 443 \
    -m limit --limit 30/second --limit-burst 200 -j ACCEPT

# Connexions établies
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Services essentiels (DHCP, DNS local)
iptables -A INPUT -i ${WIFI_IFACE} -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 53 -j ACCEPT

# Tout autre trafic WiFi est rejeté
iptables -A INPUT -i ${WIFI_IFACE} -j DROP

# ─── REDIRECTIONS NAT ─────────────────────────────────────────────────────────
# HTTP/HTTPS → portail captif
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 80 \
    -j DNAT --to-destination ${LOCAL_IP}:80
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 443 \
    -j DNAT --to-destination ${LOCAL_IP}:443

# DNS forcé : toutes les requêtes DNS WiFi → ${LOCAL_IP}:53
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p udp --dport 53 \
    -j DNAT --to-destination ${LOCAL_IP}:53
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 53 \
    -j DNAT --to-destination ${LOCAL_IP}:53
ok "DNS forcé : toutes les requêtes DNS WiFi → ${LOCAL_IP}:53"

# ─── ISOLATION FORWARD ───────────────────────────────────────────────────────
# Interdire toute communication entre clients WiFi (double sécurité avec ap_isolate)
iptables -A FORWARD -i ${WIFI_IFACE} -o ${WIFI_IFACE} -j DROP

# Bloquer tout accès Internet via ETH
iptables -A FORWARD -i ${WIFI_IFACE} -o ${ETH_IFACE} -j DROP

# Filet de sécurité : bloquer tout forward WiFi restant
iptables -A FORWARD -i ${WIFI_IFACE} -j DROP

# Sauvegarde des règles
mkdir -p /etc/iptables
netfilter-persistent save >/dev/null 2>&1
ok "Règles iptables sauvegardées (DNS forcé actif)"

# Vérification critique de l'isolation
if ! iptables -C FORWARD -i ${WIFI_IFACE} -o ${ETH_IFACE} -j DROP 2>/dev/null; then
    err "CRITIQUE : Règle isolation WiFi→Internet manquante"
    exit 1
fi
if ! iptables -C FORWARD -i ${WIFI_IFACE} -j DROP 2>/dev/null; then
    err "CRITIQUE : Filet de sécurité WiFi manquant"
    exit 1
fi
ok "Isolation WiFi → Internet : vérifiée ✓"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 10 — SYSCTL & FILESYSTEM
# ══════════════════════════════════════════════════════════════════════════════
next_step "Optimisations système"

cat > /etc/sysctl.d/60-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.${WIFI_IFACE}.disable_ipv6 = 1
net.ipv6.conf.${ETH_IFACE}.disable_ipv6 = 1
EOF

cat > /etc/sysctl.d/50-anti-spoofing.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.${WIFI_IFACE}.forwarding = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
kernel.sysrq = 0
EOF

sysctl -p /etc/sysctl.d/50-anti-spoofing.conf >/dev/null 2>&1 || true
sysctl -p /etc/sysctl.d/60-disable-ipv6.conf  >/dev/null 2>&1 || true
ok "IPv6 désactivé, sysrq=0, anti-spoofing actif"

if ! grep -q "tmpfs /var/log/nginx" /etc/fstab 2>/dev/null; then
    echo "tmpfs /var/log/nginx tmpfs defaults,noatime,nosuid,mode=0755,size=10m 0 0" >> /etc/fstab
    mkdir -p /var/log/nginx
    mount -t tmpfs tmpfs /var/log/nginx 2>/dev/null || true
    ok "Logs nginx → tmpfs (RGPD)"
fi

if ! grep -q "tmpfs /var/log/hostapd" /etc/fstab 2>/dev/null; then
    echo "tmpfs /var/log/hostapd tmpfs defaults,noatime,nosuid,mode=0755,size=5m 0 0" >> /etc/fstab
    mkdir -p /var/log/hostapd
    mount -t tmpfs tmpfs /var/log/hostapd 2>/dev/null || true
    ok "Logs hostapd → tmpfs"
fi

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 11 — ÉCONOMIE D'ÉNERGIE
# ══════════════════════════════════════════════════════════════════════════════
next_step "Économie d'énergie"

if command -v tvservice &>/dev/null; then
    tvservice -o 2>/dev/null && ok "HDMI désactivé (tvservice)" || true
elif [ -f /sys/class/drm/card0/enabled ]; then
    echo off > /sys/class/drm/card0/enabled 2>/dev/null || true
    ok "HDMI désactivé (sysfs)"
fi

if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
    ok "CPU governor → ondemand"
fi

info "Consommation estimée : 3-5W sur batterie externe"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 12 — NGINX & CRÉATION config.json
# ══════════════════════════════════════════════════════════════════════════════
next_step "Serveur web Nginx + Configuration JSON"

WEB_DIR="/var/www/sos-guide"
mkdir -p ${WEB_DIR}/img ${WEB_DIR}/data

# Copier les fichiers web depuis la structure du dépôt
progress "Copie des fichiers HTML"
cp web/index.html ${WEB_DIR}/
cp web/admin.php ${WEB_DIR}/
cp web/update_config.php ${WEB_DIR}/
ok "Fichiers HTML copiés"

# Copier les dossiers de langue (tous les sous-dossiers de web/data/)
step "Copie des fichiers de langue..."
for lang_file in web/data/*.json; do
    if [ -f "$lang_file" ]; then
        cp "$lang_file" "${WEB_DIR}/data/"
        ok "Langue $(basename "$lang_file" .json) copiée"
    fi
done

# --- CRÉATION DU FICHIER config.json avec jq pour échappement correct ---
CONFIG_JSON="${WEB_DIR}/data/config.json"
jq -n \
    --arg name "$LOC_NAME" \
    --arg address "$LOC_ADDRESS" \
    --arg lat "$LOC_LAT" \
    --arg lon "$LOC_LON" \
    --arg type "$ESTABLISHMENT_TYPE" \
    --arg crisis "$LOCAL_CRISIS_NUMBER" \
    --arg risk "$LOCAL_RISK" \
    --arg samu "$LOCAL_SAMU_NUMBER" \
    --arg pompiers "$LOCAL_POMPIERS_NUMBER" \
    --arg mairie "$LOCAL_MAIRIE_NUMBER" \
    --arg prefecture "$LOCAL_PREFECTURE" \
    --arg dsden "$LOCAL_DSDEN" \
    --arg radio "$LOCAL_RADIO_FREQ" \
    --arg croixrouge "$LOCAL_CROIX_ROUGE" \
    --arg pcc "$LOCAL_PCC_ADDRESS" \
    --arg meeting "$LOCAL_MEETING_POINT" \
    --arg evacuation "$LOCAL_EVACUATION_PLAN" \
    --arg reassurance "$REASSURANCE_MESSAGE" \
    '{
        establishment: {
            name: $name,
            address: $address,
            lat: $lat,
            lon: $lon,
            type: $type,
            localCrisisNumber: $crisis,
            localRisk: $risk,
            localSamuNumber: $samu,
            localPompiersNumber: $pompiers,
            localMairieNumber: $mairie,
            localPrefecture: $prefecture,
            localDsden: $dsden,
            localRadioFreq: $radio,
            localCroixRouge: $croixrouge,
            localPccAddress: $pcc,
            localMeetingPoint: $meeting,
            localEvacuationPlan: $evacuation
        },
        reassurance: {
            message: $reassurance
        }
    }' > "$CONFIG_JSON"

chown www-data:www-data "$CONFIG_JSON"
chmod 644 "$CONFIG_JSON"
ok "Fichier config.json créé"

# --- Copie de la carte PNG si disponible
if [ "${COPY_CUSTOM_IMAGE}" = true ]; then
    if cp "${CUSTOM_IMAGE_SOURCE}" "${WEB_DIR}/img/map_location.png"; then
        chown www-data:www-data "${WEB_DIR}/img/map_location.png"
        chmod 644 "${WEB_DIR}/img/map_location.png"
        ok "Carte PNG copiée → zoomable sur le portail"
    else
        warn "Échec copie carte PNG"
    fi
fi

chown -R www-data:www-data ${WEB_DIR}
chmod -R 755 ${WEB_DIR}
find ${WEB_DIR}/data -type f -exec chmod 644 {} \;

# --- Génération certificat SSL
step "Génération certificat SSL auto-signé..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/sos-guide.key \
    -out /etc/ssl/certs/sos-guide.crt \
    -subj "/C=FR/ST=Emergency/L=Local/O=SOS-GUIDE/CN=${LOCAL_IP}" 2>/dev/null
chmod 600 /etc/ssl/private/sos-guide.key
ok "Certificat SSL 365 jours généré"

# --- Configuration nginx avec PHP
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/sos-guide <<'NGINXEOF'
server {
    listen 80 default_server;
    # listen [::]:80 default_server;   # IPv6 désactivé
    server_name _;
    root /var/www/sos-guide;
    index index.php index.html;
    access_log off;
    error_log off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 3;
    types_hash_max_size 2048;

    # Redirections pour portail captif
    location = /hotspot-detect.html       { return 302 http://10.0.0.1/; }
    location = /library/test/success.html { return 302 http://10.0.0.1/; }
    location = /generate_204              { return 302 http://10.0.0.1/; }
    location = /generate_205              { return 302 http://10.0.0.1/; }
    location = /gen_204                   { return 302 http://10.0.0.1/; }
    location = /connecttest.txt           { return 302 http://10.0.0.1/; }
    location = /ncsi.txt                  { return 302 http://10.0.0.1/; }
    location = /success.txt               { return 302 http://10.0.0.1/; }
    location = /canonical.html            { return 302 http://10.0.0.1/; }
    location = /fwlink/                   { return 302 http://10.0.0.1/; }

    location = /health {
        access_log off; default_type text/plain;
        add_header Cache-Control "no-store";
        return 200 "OK\n";
    }

    location = /ping {
        access_log off; default_type text/plain;
        add_header Cache-Control "no-store";
        return 200 "SOS-GUIDE reachable\n";
    }

    # --- Admin protégé
    location /admin {
        auth_basic "Administration SOS-GUIDE";
        auth_basic_user_file /etc/nginx/.htpasswd;
        try_files $uri $uri/ =404;
    }

    # --- Fichiers PHP
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/phpPHP_VERSION-fpm.sock;
    }

    location /img/  { alias /var/www/sos-guide/img/;  expires 1y; add_header Cache-Control "public, immutable"; }
    location /data/ { alias /var/www/sos-guide/data/; add_header Cache-Control "no-store"; }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
        add_header X-Content-Type-Options "nosniff";
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Robots-Tag "noindex, nofollow";
    }

    location ~ /\. { deny all; access_log off; log_not_found off; }
    location ~* \.(env|ini|log|sh|sql|conf|cfg)$ { deny all; access_log off; log_not_found off; }
}

server {
    listen 443 ssl default_server;
    # listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/certs/sos-guide.crt;
    ssl_certificate_key /etc/ssl/private/sos-guide.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!3DES;
    ssl_prefer_server_ciphers on;
    access_log off; error_log off;
    root /var/www/sos-guide;
    index index.php index.html;

    location = /hotspot-detect.html       { return 302 http://10.0.0.1/; }
    location = /library/test/success.html { return 302 http://10.0.0.1/; }
    location = /generate_204              { return 302 http://10.0.0.1/; }
    location = /gen_204                   { return 302 http://10.0.0.1/; }
    location /                            { return 302 http://10.0.0.1/; }
}

server {
    listen 80;
    server_name connectivitycheck.gstatic.com connectivitycheck.android.com
                connectivitycheck.hicloud.com connect.rom.miui.com
                wifi.vivo.com.cn www.samsung.com;
    access_log off; error_log /dev/null;
    location = /generate_204 { return 302 http://10.0.0.1/; }
    location /               { return 302 http://10.0.0.1/; }
}
NGINXEOF

# Remplacer la variable PHP_VERSION dans le fichier nginx
sed -i "s|phpPHP_VERSION|php${PHP_VERSION}|g" /etc/nginx/sites-available/sos-guide
ln -sf /etc/nginx/sites-available/sos-guide /etc/nginx/sites-enabled/
nginx -t >/dev/null 2>&1
systemctl unmask nginx 2>/dev/null || true
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx >/dev/null 2>&1
ok "Serveur web HTTP + HTTPS + portail captif multi-OS"

# --- Création du mot de passe admin
next_step "Configuration administrateur"
read -s -p "  🔐  Mot de passe pour l'administration : " ADMIN_PASS
echo
if [ -n "$ADMIN_PASS" ]; then
    printf "%s" "$ADMIN_PASS" | htpasswd -i -c /etc/nginx/.htpasswd admin
    chmod 600 /etc/nginx/.htpasswd
    ok "Utilisateur admin créé"
else
    printf "sosguide2026" | htpasswd -i -c /etc/nginx/.htpasswd admin
    warn "Mot de passe admin par défaut : sosguide2026 (à changer)"
fi

# Démarrage PHP-FPM
systemctl enable php${PHP_VERSION}-fpm 2>/dev/null || true
systemctl restart php${PHP_VERSION}-fpm 2>/dev/null || true
ok "PHP-FPM démarré"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 13 — VERROUILLAGE WEB (data/ exclu pour admin)
# ══════════════════════════════════════════════════════════════════════════════
next_step "Verrouillage du contenu web"

chmod -R a-w ${WEB_DIR}/
# Exclure le dossier data/ pour permettre l'admin web
if command -v chattr &>/dev/null; then
    find ${WEB_DIR} -type f ! -path "${WEB_DIR}/data/*" -exec chattr +i {} \; 2>/dev/null
    chattr -R -i ${WEB_DIR}/data/ 2>/dev/null || true
    chmod 755 ${WEB_DIR}/data/
    chown www-data:www-data ${WEB_DIR}/data/
    ok "chattr +i verrouillage immuable (data/ exclu pour admin)"
else
    warn "chattr non supporté sur ce FS"
fi

info "Modification : sudo bash /usr/local/bin/sos-guide-update-content.sh"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 14 — WATCHDOG + INTÉGRITÉ
# ══════════════════════════════════════════════════════════════════════════════
next_step "Watchdog hardware + Intégrité SHA256"

for cfg in /boot/firmware/config.txt /boot/config.txt; do
    [ -f "$cfg" ] || continue
    # Supprimer les lignes dtparam=watchdog existantes puis ajouter la bonne
    sed -i '/^dtparam=watchdog/d' "$cfg"
    echo "dtparam=watchdog=on" >> "$cfg"
    break
done

modprobe bcm2835_wdt 2>/dev/null || true
if [ -e /dev/watchdog ]; then
    cat > /etc/watchdog.conf <<'EOF'
watchdog-device = /dev/watchdog
watchdog-timeout = 14
max-load-1 = 24
max-load-5 = 18
max-load-15 = 12
realtime = yes
priority = 1
EOF
    systemctl unmask watchdog 2>/dev/null || true
    systemctl enable watchdog >/dev/null 2>&1 || true
    systemctl start watchdog >/dev/null 2>&1 || true
    ok "Watchdog hardware actif (timeout 14s)"
else
    warn "Watchdog hardware non disponible — fallback logiciel"
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/watchdog.conf <<EOF
[Manager]
RuntimeWatchdogSec=14s
ShutdownWatchdogSec=10min
EOF
    systemctl daemon-reload >/dev/null 2>&1
fi

progress "Calcul hash SHA256 intégrité"
find ${WEB_DIR} -type f -exec sha256sum {} \; > /root/integrity.hash
sha256sum /etc/nginx/sites-available/sos-guide >> /root/integrity.hash
ok "Hash d'intégrité généré : /root/integrity.hash"

WFACE="${WIFI_IFACE}"
EFACE="${ETH_IFACE}"

# Génération dynamique du script de boot-check
cat > /usr/local/bin/sos-guide-boot-check.sh << BOOTEOF
#!/bin/bash
WFACE="${WFACE}"
EFACE="${EFACE}"
if [ -f /root/integrity.hash ]; then
    if ! sha256sum -c /root/integrity.hash >/dev/null 2>&1; then
        logger "SOS-GUIDE: INTEGRITE COMPROMISE - SHUTDOWN"
        poweroff
    fi
fi
if ! iptables -C FORWARD -i \${WFACE} -o \${EFACE} -j DROP 2>/dev/null; then
    logger "SOS-GUIDE: CRITIQUE - Isolation Internet COMPROMISE"
    iptables -P FORWARD DROP
    iptables -A FORWARD -i \${WFACE} -o \${WFACE} -j DROP
    iptables -A FORWARD -i \${WFACE} -o \${EFACE} -j DROP
    iptables -A FORWARD -i \${WFACE} -j DROP
    logger "SOS-GUIDE: Regles isolation RESTAUREES"
fi
if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "MASQUERADE\|SNAT"; then
    logger "SOS-GUIDE: ALERTE - Regle NAT sortante detectee (SUPPRIMEE)"
    iptables -t nat -F POSTROUTING
fi
BOOTEOF

chmod +x /usr/local/bin/sos-guide-boot-check.sh

cat > /etc/systemd/system/sos-guide-boot.service << 'SVC'
[Unit]
Description=SOS-GUIDE Boot Integrity & Firewall Check
After=network.target iptables.service netfilter-persistent.service
Wants=network.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/sos-guide-boot-check.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload >/dev/null 2>&1
systemctl enable sos-guide-boot.service >/dev/null 2>&1 || true
ok "Service boot-check activé"

cat > /usr/local/bin/sos-guide-health.sh << HEALTHEOF
#!/bin/bash
ERRORS=0
WFACE="${WFACE}"
EFACE="${EFACE}"
for svc in hostapd dnsmasq nginx; do
    if ! systemctl is-active --quiet \$svc; then
        logger "SOS-GUIDE: SERVICE \$svc DOWN - redemarrage"
        systemctl restart \$svc 2>/dev/null || true
        ERRORS=\$((ERRORS+1))
    fi
done
if ! iptables -C FORWARD -i \${WFACE} -o \${EFACE} -j DROP 2>/dev/null; then
    logger "SOS-GUIDE: ISOLATION COMPROMISE - restauration firewall"
    iptables -P FORWARD DROP
    iptables -A FORWARD -i \${WFACE} -o \${EFACE} -j DROP
    iptables -A FORWARD -i \${WFACE} -j DROP
    ERRORS=\$((ERRORS+1))
fi
[ \$ERRORS -gt 0 ] && logger "SOS-GUIDE: health-check: \$ERRORS anomalie(s) corrigee(s)"
exit 0
HEALTHEOF

chmod +x /usr/local/bin/sos-guide-health.sh

cat > /etc/systemd/system/sos-guide-health.service << 'SVC'
[Unit]
Description=SOS-GUIDE Health Check

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sos-guide-health.sh
SVC

cat > /etc/systemd/system/sos-guide-health.timer << 'TMR'
[Unit]
Description=SOS-GUIDE Health Check toutes les 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=sos-guide-health.service

[Install]
WantedBy=timers.target
TMR

systemctl daemon-reload >/dev/null 2>&1
systemctl enable sos-guide-health.timer >/dev/null 2>&1
systemctl start sos-guide-health.timer >/dev/null 2>&1
ok "Health check toutes les 5 minutes"

cat > /usr/local/bin/sos-guide-renew-cert.sh << 'CERTEOF'
#!/bin/bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/sos-guide.key \
    -out /etc/ssl/certs/sos-guide.crt \
    -subj "/C=FR/ST=Emergency/L=Local/O=SOS-GUIDE/CN=10.0.0.1" 2>/dev/null
chmod 600 /etc/ssl/private/sos-guide.key
systemctl reload nginx 2>/dev/null || true
logger "SOS-GUIDE: Certificat SSL renouvelé"
CERTEOF

chmod +x /usr/local/bin/sos-guide-renew-cert.sh

cat > /etc/systemd/system/sos-guide-renew-cert.service << 'SVC'
[Unit]
Description=SOS-GUIDE SSL Certificate Renewal

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sos-guide-renew-cert.sh
SVC

cat > /etc/systemd/system/sos-guide-renew-cert.timer << 'TMR'
[Unit]
Description=Renouvellement certificat SSL SOS-GUIDE

[Timer]
OnCalendar=annually
Persistent=true

[Install]
WantedBy=timers.target
TMR

systemctl daemon-reload >/dev/null 2>&1
systemctl enable sos-guide-renew-cert.timer >/dev/null 2>&1
ok "Renouvellement SSL automatique (annuel)"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 15 — TESTS DE VALIDATION
# ══════════════════════════════════════════════════════════════════════════════
next_step "Tests de validation"

step "Attente que ${WIFI_IFACE} soit en mode AP..."
for i in {1..15}; do
    if iw dev ${WIFI_IFACE} info 2>/dev/null | grep -q "type AP"; then
        ok "Interface ${WIFI_IFACE} en mode AP"
        break
    fi
    sleep 2
    if [ $i -eq 15 ]; then
        warn "Délai d'attente dépassé, l'interface n'est pas en mode AP"
    fi
done

TESTS_OK=0
TESTS_TOTAL=5
echo ""

# Test DNS wildcard avec dig (installé via dnsutils)
if command -v dig &>/dev/null; then
    DNS_RESULT=$(dig +short @${LOCAL_IP} google.com 2>/dev/null | tail -1)
    if [ "${DNS_RESULT}" = "${LOCAL_IP}" ]; then
        ok "DNS wildcard → ${LOCAL_IP} (spoofing OK)"
        TESTS_OK=$((TESTS_OK+1))
    else
        warn "DNS wildcard : résultat inattendu (${DNS_RESULT:-aucun})"
    fi
else
    TESTS_TOTAL=$((TESTS_TOTAL-1))
fi

for PROBE in "/hotspot-detect.html:iOS" "/generate_204:Android" "/connecttest.txt:Windows"; do
    URL="${PROBE%%:*}"; LABEL="${PROBE##*:}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${LOCAL_IP}${URL} 2>/dev/null || echo "000")
    if [ "${CODE}" = "302" ]; then
        ok "Probe ${LABEL} → 302 (portail détecté)"
        TESTS_OK=$((TESTS_OK+1))
    else
        warn "Probe ${LABEL} → code ${CODE} (attendu 302)"
    fi
done

CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${LOCAL_IP}/ 2>/dev/null || echo "000")
if [ "${CODE}" = "200" ]; then
    ok "Portail principal → 200 OK"
    TESTS_OK=$((TESTS_OK+1))
else
    warn "Portail principal → code ${CODE}"
fi

if ! ping -c1 -W1 -I ${WIFI_IFACE} 8.8.8.8 &>/dev/null; then
    ok "Isolation Internet active (${WIFI_IFACE} → 8.8.8.8 BLOQUÉ)"
    TESTS_OK=$((TESTS_OK+1))
else
    err "ALERTE CRITIQUE : ${WIFI_IFACE} peut accéder à Internet !"
fi

echo ""
if [ $TESTS_OK -eq $TESTS_TOTAL ]; then
    echo -e "  ${GREEN}${BOLD}✔  Tous les tests passés (${TESTS_OK}/${TESTS_TOTAL})${NC}"
else
    echo -e "  ${YELLOW}⚠  ${TESTS_OK}/${TESTS_TOTAL} tests réussis — vérifiez ci-dessus${NC}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 16 — SCRIPTS DE MAINTENANCE
# ══════════════════════════════════════════════════════════════════════════════
next_step "Scripts de maintenance"

cat > /usr/local/bin/sos-guide-update-content.sh << 'UPDATEEOF'
#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
[ "$(id -u)" -ne 0 ] && { echo -e "${RED}Root requis${NC}"; exit 1; }
echo -e "${YELLOW}[1/3] Déverrouillage...${NC}"
chattr -R -i /var/www/sos-guide/ 2>/dev/null || true
chmod -R u+w /var/www/sos-guide/
echo -e "${GREEN}✔ Contenu déverrouillé — modifiez /var/www/sos-guide/${NC}"
read -p "Appuyez sur [Entrée] quand vous avez terminé..."
echo -e "${YELLOW}[2/3] Reverrouillage...${NC}"
chown -R www-data:www-data /var/www/sos-guide/
chmod -R a-w /var/www/sos-guide/
chattr -R +i /var/www/sos-guide/ 2>/dev/null || true
chattr -R -i /var/www/sos-guide/data/ 2>/dev/null || true
echo -e "${YELLOW}[3/3] Régénération hash...${NC}"
find /var/www/sos-guide -type f -exec sha256sum {} \; > /root/integrity.hash
sha256sum /etc/nginx/sites-available/sos-guide >> /root/integrity.hash
echo -e "${GREEN}✔ Mise à jour terminée. Test : curl http://10.0.0.1/${NC}"
UPDATEEOF

chmod +x /usr/local/bin/sos-guide-update-content.sh
ok "sos-guide-update-content.sh"

cat > /usr/local/bin/sos-guide-copy-image.sh << 'IMGEOF'
#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
WEB_DIR="/var/www/sos-guide"
[ "$(id -u)" -ne 0 ] && { echo -e "${RED}Root requis${NC}"; exit 1; }
IMG="${1:-/home/pi/map_location.png}"
[ ! -f "${IMG}" ] && { echo -e "${RED}Fichier introuvable : ${IMG}${NC}"; exit 1; }
echo -e "${YELLOW}[1/4] Déverrouillage...${NC}"
chattr -R -i ${WEB_DIR}/ 2>/dev/null || true; chmod -R u+w ${WEB_DIR}/
echo -e "${YELLOW}[2/4] Copie...${NC}"
cp "${IMG}" "${WEB_DIR}/img/map_location.png"
chown www-data:www-data "${WEB_DIR}/img/map_location.png"
chmod 644 "${WEB_DIR}/img/map_location.png"
echo -e "${YELLOW}[3/4] Reverrouillage...${NC}"
chmod -R a-w ${WEB_DIR}/; chattr -R +i ${WEB_DIR}/ 2>/dev/null || true
chattr -R -i ${WEB_DIR}/data/ 2>/dev/null || true
echo -e "${YELLOW}[4/4] Hash...${NC}"
find ${WEB_DIR} -type f -exec sha256sum {} \; > /root/integrity.hash
sha256sum /etc/nginx/sites-available/sos-guide >> /root/integrity.hash
echo -e "${GREEN}✔ Carte PNG installée → http://10.0.0.1/img/map_location.png${NC}"
IMGEOF

chmod +x /usr/local/bin/sos-guide-copy-image.sh
ok "sos-guide-copy-image.sh"

# Installation du script de mise à jour automatique
step "Installation du script de mise à jour automatique..."
if [ -f "sos-guide-update.sh" ]; then
    cp sos-guide-update.sh /usr/local/bin/sos-guide-update.sh
    chmod +x /usr/local/bin/sos-guide-update.sh
    ok "sos-guide-update.sh installé"
else
    warn "sos-guide-update.sh manquant"
fi

# Timer pour mise à jour auto
cat > /etc/systemd/system/sos-guide-update.service << 'SVC'
[Unit]
Description=SOS-GUIDE Content Update Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sos-guide-update.sh auto
StandardOutput=journal
StandardError=journal
SVC

cat > /etc/systemd/system/sos-guide-update.timer << 'TMR'
[Unit]
Description=SOS-GUIDE Content Update — vérification toutes les 6h

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
TMR

systemctl daemon-reload >/dev/null 2>&1
systemctl enable sos-guide-update.timer >/dev/null 2>&1
systemctl start sos-guide-update.timer >/dev/null 2>&1
ok "Timer mise à jour : vérification toutes les 6h"
info "Version installée : $(cat /root/sos-guide-content-version.txt 2>/dev/null || echo 'aucune')"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 17 — SCRIPTS DEBUG
# ══════════════════════════════════════════════════════════════════════════════
next_step "Scripts debug SSH (accès temporaire sécurisé)"
WFACE_S="${WIFI_IFACE}"
EFACE_S="${ETH_IFACE}"
ETH_ONLY_S="${ETH_MODE_ONLY}"

cat > /usr/local/bin/sos-guide-debug-stop.sh << STOPEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
DEBUG_ETH_IP="10.0.0.254"
ETH_IFACE="${EFACE_S}"
WLAN_IFACE="${WFACE_S}"
MODE="\${1:-manual}"
ip addr del \${DEBUG_ETH_IP}/24 dev \${ETH_IFACE} 2>/dev/null || true
iptables -D INPUT -i \${ETH_IFACE} -p tcp --dport 22 \
    -d \${DEBUG_ETH_IP} -m conntrack --ctstate NEW \
    -m limit --limit 3/min --limit-burst 3 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -i \${WLAN_IFACE} -p tcp --dport 22 \
    -m conntrack --ctstate NEW \
    -m limit --limit 2/min --limit-burst 2 -j ACCEPT 2>/dev/null || true
for PID_FILE in /tmp/sos-debug-eth.pid /tmp/sos-debug-wlan.pid; do
    if [ -f "\${PID_FILE}" ]; then
        kill \$(cat "\${PID_FILE}") 2>/dev/null || true
        rm -f "\${PID_FILE}"
    fi
done
rm -f /tmp/sos-debug-eth.lock /tmp/sos-debug-wlan.lock
if [ "\${MODE}" = "auto" ]; then
    logger "SOS-GUIDE: debug-mode auto-désactivé (timeout)"
    echo -e "\${YELLOW}⏱  SSH debug auto-désactivé — session existante maintenue\${NC}"
else
    echo -e "\${GREEN}✔  SSH debug désactivé — session existante maintenue\${NC}"
fi
STOPEOF

chmod +x /usr/local/bin/sos-guide-debug-stop.sh
ok "sos-guide-debug-stop.sh"

# Script debug ETH
cat > /usr/local/bin/sos-guide-debug.sh << DEBUGEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'
DEBUG_IP="10.0.0.254"
ETH_IFACE="${EFACE_S}"
DURATION=1800
LOCK_FILE="/tmp/sos-debug-eth.lock"
[ "\$(id -u)" -ne 0 ] && { echo -e "\${RED}Root requis : sudo bash \$0\${NC}"; exit 1; }
if [ -f "\${LOCK_FILE}" ]; then
    echo -e "\${YELLOW}⚠  Debug ETH déjà actif — IP : \${DEBUG_IP}\${NC}"
    read -p "Désactiver maintenant ? (o/N) : " C
    [ "\${C}" = "o" ] || [ "\${C}" = "O" ] && bash /usr/local/bin/sos-guide-debug-stop.sh
    exit 0
fi
if ! ip link show "\${ETH_IFACE}" &>/dev/null; then
    echo -e "\${RED}✘  Interface \${ETH_IFACE} introuvable\${NC}"
    echo -e "\${CYAN}   Branchez le câble Ethernet puis relancez\${NC}"
    exit 1
fi
echo ""
echo -e "\${BOLD}\${MAGENTA}╔══════════════════════════════════════╗\${NC}"
echo -e "\${BOLD}\${MAGENTA}║   🔧  DEBUG MODE ETH — 30 MINUTES   ║\${NC}"
echo -e "\${BOLD}\${MAGENTA}╚══════════════════════════════════════╝\${NC}"
echo ""
echo -e "\${YELLOW}⚠  SSH ouvert sur \${DEBUG_IP} via câble ETH\${NC}"
echo -e "\${YELLOW}   Auto-désactivation dans 30 min\${NC}"
echo -e "\${YELLOW}   Session active = maintenue après expiration\${NC}"
echo ""
read -p "Confirmer ? (o/N) : " C
[ "\${C}" != "o" ] && [ "\${C}" != "O" ] && { echo -e "\${CYAN}Annulé\${NC}"; exit 0; }
echo -e "\${BLUE}[1/3] Ajout IP \${DEBUG_IP}/24 sur \${ETH_IFACE}...\${NC}"
ip addr add \${DEBUG_IP}/24 dev \${ETH_IFACE} 2>/dev/null || true
ip link set \${ETH_IFACE} up
echo -e "\${BLUE}[2/3] Ouverture SSH sur \${DEBUG_IP}...\${NC}"
iptables -I INPUT 1 -i \${ETH_IFACE} -p tcp --dport 22 \
    -d \${DEBUG_IP} -m conntrack --ctstate NEW \
    -m limit --limit 3/min --limit-burst 3 -j ACCEPT
echo -e "\${BLUE}[3/3] Timer 30 min...\${NC}"
( sleep \${DURATION}; bash /usr/local/bin/sos-guide-debug-stop.sh auto ) &
echo \$! > /tmp/sos-debug-eth.pid
echo \${DURATION} > "\${LOCK_FILE}"
echo ""
echo -e "\${GREEN}✔  DEBUG ETH ACTIF — 30 MINUTES\${NC}"
echo ""
echo -e "\${CYAN}Sur ton PC (Arch Linux) :\${NC}"
echo -e "   sudo ip addr add 10.0.0.2/24 dev <interface_eth>"
echo -e "   sudo ip route add 10.0.0.0/24 dev <interface_eth>"
echo -e "   ssh pi@\${DEBUG_IP}"
echo ""
echo -e "\${YELLOW}⏱  Désactivation manuelle : sudo bash /usr/local/bin/sos-guide-debug-stop.sh\${NC}"
DEBUGEOF

chmod +x /usr/local/bin/sos-guide-debug.sh
ok "sos-guide-debug.sh (ETH câble direct, 30 min)"

# Script debug WLAN
cat > /usr/local/bin/sos-guide-debug-wlan.sh << WLANDEBUGEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'
WLAN_IFACE="${WFACE_S}"
LOCAL_IP="10.0.0.1"
DURATION=600
LOCK_FILE="/tmp/sos-debug-wlan.lock"
[ "\$(id -u)" -ne 0 ] && { echo -e "\${RED}Root requis : sudo bash \$0\${NC}"; exit 1; }
if [ -f "\${LOCK_FILE}" ]; then
    echo -e "\${YELLOW}⚠  Debug WiFi déjà actif — IP : \${LOCAL_IP}\${NC}"
    read -p "Désactiver maintenant ? (o/N) : " C
    [ "\${C}" = "o" ] || [ "\${C}" = "O" ] && bash /usr/local/bin/sos-guide-debug-stop.sh
    exit 0
fi
echo ""
echo -e "\${BOLD}\${MAGENTA}╔══════════════════════════════════════╗\${NC}"
echo -e "\${BOLD}\${MAGENTA}║   📡  DEBUG MODE WLAN — 10 MINUTES  ║\${NC}"
echo -e "\${BOLD}\${MAGENTA}╚══════════════════════════════════════╝\${NC}"
echo ""
echo -e "\${RED}⚠  SSH ouvert sur le réseau WiFi SOS-GUIDE\${NC}"
echo -e "\${RED}   Tout appareil connecté au WiFi peut tenter SSH\${NC}"
echo -e "\${YELLOW}   Auto-désactivation dans 10 min\${NC}"
echo -e "\${YELLOW}   Session active = maintenue après expiration\${NC}"
echo -e "\${YELLOW}   Réserver à un usage d'urgence admin uniquement\${NC}"
echo ""
read -p "Confirmer le mode WLAN ? (o/N) : " C
[ "\${C}" != "o" ] && [ "\${C}" != "O" ] && { echo -e "\${CYAN}Annulé\${NC}"; exit 0; }
echo -e "\${BLUE}[1/2] Ouverture SSH sur \${WLAN_IFACE} (\${LOCAL_IP})...\${NC}"
iptables -I INPUT 1 -i \${WLAN_IFACE} -p tcp --dport 22 \
    -m conntrack --ctstate NEW \
    -m limit --limit 2/min --limit-burst 2 -j ACCEPT
echo -e "\${BLUE}[2/2] Timer 10 min...\${NC}"
( sleep \${DURATION}; bash /usr/local/bin/sos-guide-debug-stop.sh auto ) &
echo \$! > /tmp/sos-debug-wlan.pid
echo \${DURATION} > "\${LOCK_FILE}"
echo ""
echo -e "\${GREEN}✔  DEBUG WLAN ACTIF — 10 MINUTES\${NC}"
echo ""
echo -e "\${CYAN}Connecte ton PC au WiFi ⛑️ SOS-GUIDE puis :\${NC}"
echo -e "   ssh pi@\${LOCAL_IP}"
echo ""
echo -e "\${YELLOW}⏱  Désactivation manuelle : sudo bash /usr/local/bin/sos-guide-debug-stop.sh\${NC}"
WLANDEBUGEOF

chmod +x /usr/local/bin/sos-guide-debug-wlan.sh
ok "sos-guide-debug-wlan.sh (WiFi SOS-GUIDE, 10 min)"
ok "sos-guide-debug-stop.sh (désactivation commune)"
info "Session SSH existante MAINTENUE après expiration du timer (iptables ESTABLISHED)"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 18 — RÉSUMÉ FINAL
# ══════════════════════════════════════════════════════════════════════════════
ETH_IP=$(ip -4 addr show "${ETH_IFACE}" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "non connecté")

clear
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════════════════╗"
echo "  ║                                                                      ║"
echo "  ║      ✅   S O S - G U I D E   v 2 . 1   —   P R Ê T  !                ║"
echo "  ║                                                                      ║"
echo "  ╚══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
sep_bold
echo -e "  ${BOLD}${CYAN}📡  RÉSEAU${NC}"
sep
echo -e "  ${GREEN}✔${NC}  WiFi AP     : ${BOLD}${SSID}${NC}"
echo -e "  ${GREEN}✔${NC}  IP portail  : ${BOLD}${LOCAL_IP}${NC}"
echo -e "  ${GREEN}✔${NC}  Interface   : ${WIFI_IFACE}  (réseau ouvert, ap_isolate)"
if [ "${ETH_MODE_ONLY}" = false ]; then
    echo -e "  ${GREEN}✔${NC}  ETH IP      : ${ETH_IP}  (DHCP modem)"
    echo -e "  ${GREEN}✔${NC}  Accès SSH   : ssh pi@${ETH_IP} (ou via l'IP DHCP)"
else
    echo -e "  ${YELLOW}–${NC}  ETH         : non connecté (mode WiFi seul)"
fi
sep_bold
echo -e "  ${BOLD}${CYAN}🏢  LIEU${NC}"
sep
echo -e "  ${GREEN}✔${NC}  Nom         : ${LOC_NAME}"
echo -e "  ${GREEN}✔${NC}  Adresse     : ${LOC_ADDRESS}"
[ -n "${LOC_LAT}" ] && echo -e "  ${GREEN}✔${NC}  GPS         : ${LOC_LAT}, ${LOC_LON}"
echo -e "  ${GREEN}✔${NC}  Type        : ${ESTABLISHMENT_TYPE}"
sep_bold
echo -e "  ${BOLD}${CYAN}📞  CONTACTS LOCAUX${NC}"
sep
[ -n "${LOCAL_CRISIS_NUMBER}"   ] && echo -e "  ${GREEN}✔${NC}  Crise locale        : ${LOCAL_CRISIS_NUMBER}"   || echo -e "  ${YELLOW}–${NC}  Crise locale        : non renseigné"
[ -n "${LOCAL_SAMU_NUMBER}"     ] && echo -e "  ${GREEN}✔${NC}  SAMU local          : ${LOCAL_SAMU_NUMBER}"
[ -n "${LOCAL_POMPIERS_NUMBER}" ] && echo -e "  ${GREEN}✔${NC}  Pompiers locaux     : ${LOCAL_POMPIERS_NUMBER}"
[ -n "${LOCAL_MAIRIE_NUMBER}"   ] && echo -e "  ${GREEN}✔${NC}  Mairie              : ${LOCAL_MAIRIE_NUMBER}"
[ -n "${LOCAL_PREFECTURE}"      ] && echo -e "  ${GREEN}✔${NC}  Préfecture          : ${LOCAL_PREFECTURE}"
[ -n "${LOCAL_RADIO_FREQ}"      ] && echo -e "  ${GREEN}✔${NC}  Radio locale        : ${LOCAL_RADIO_FREQ} MHz"
[ -n "${LOCAL_MEETING_POINT}"   ] && echo -e "  ${GREEN}✔${NC}  Point rassemblement : ${LOCAL_MEETING_POINT}"
[ -n "${LOCAL_RISK}"            ] && echo -e "  ${GREEN}✔${NC}  Risque local        : ${LOCAL_RISK}"
[ "${COPY_CUSTOM_IMAGE}" = true ] && echo -e "  ${GREEN}✔${NC}  Carte PNG           : installée (zoomable)" \
    || echo -e "  ${YELLOW}–${NC}  Carte PNG           : non installée"
sep_bold
echo -e "  ${BOLD}${CYAN}🔒  SÉCURITÉ${NC}"
sep
echo -e "  ${GREEN}✔${NC}  Clients WiFi isolés d'Internet"
echo -e "  ${GREEN}✔${NC}  Isolation client-client (ap_isolate=1)"
echo -e "  ${GREEN}✔${NC}  IPv6 désactivé"
echo -e "  ${GREEN}✔${NC}  Watchdog auto-reboot"
echo -e "  ${GREEN}✔${NC}  Intégrité SHA256 au boot"
echo -e "  ${GREEN}✔${NC}  Health check toutes les 5 min"
echo -e "  ${GREEN}✔${NC}  SSH : ETH uniquement (jamais WiFi en permanence)"
sep_bold
echo -e "  ${BOLD}${CYAN}🌐  ADMINISTRATION${NC}"
sep
echo -e "  ${GREEN}✔${NC}  Interface admin : http://${LOCAL_IP}/admin"
echo -e "  ${GREEN}✔${NC}  Identifiant : admin"
echo -e "  ${GREEN}✔${NC}  Mot de passe : (défini lors de l'installation)"
echo -e "  ${GREEN}✔${NC}  Modifiez le message de réassurance et les paramètres locaux"
sep_bold
echo -e "  ${BOLD}${CYAN}🔧  COMMANDES ADMIN${NC}"
sep
echo -e "  ${CYAN}sudo bash /usr/local/bin/sos-guide-update-content.sh${NC} ${DIM}# Modifier contenu web${NC}"
echo -e "  ${CYAN}sudo bash /usr/local/bin/sos-guide-copy-image.sh${NC}      ${DIM}# Copier carte PNG${NC}"
echo -e "  ${CYAN}sudo bash /usr/local/bin/sos-guide-update.sh${NC}           ${DIM}# Mise à jour JSON depuis sos-guide.fr${NC}"
echo -e "  ${CYAN}sudo bash /usr/local/bin/sos-guide-update.sh check${NC}     ${DIM}# Vérifier si MAJ disponible${NC}"
echo -e "  ${CYAN}sha256sum -c /root/integrity.hash${NC}                     ${DIM}# Vérifier intégrité${NC}"
echo -e "  ${CYAN}cat /root/sos-guide-content-version.txt${NC}               ${DIM}# Version contenu installée${NC}"
echo -e "  ${CYAN}journalctl -u sos-guide-update -f${NC}                     ${DIM}# Logs mises à jour${NC}"
echo ""
echo -e "  ${BOLD}${MAGENTA}🔌  ACCÈS SSH ADMIN (câble direct — 30 min)${NC}"
echo -e "  ${MAGENTA}sudo bash /usr/local/bin/sos-guide-debug.sh${NC}          ${DIM}# Via câble ETH${NC}"
echo -e "  ${CYAN}  → PC : sudo ip addr add 10.0.0.2/24 dev <eth>${NC}"
echo -e "  ${CYAN}  → SSH : ssh pi@10.0.0.254${NC}"
echo ""
echo -e "  ${BOLD}${MAGENTA}📡  ACCÈS SSH ADMIN (WiFi sans câble — 10 min)${NC}"
echo -e "  ${MAGENTA}sudo bash /usr/local/bin/sos-guide-debug-wlan.sh${NC}     ${DIM}# Via WiFi SOS-GUIDE${NC}"
echo -e "  ${CYAN}  → Connecter PC au WiFi ⛑️ SOS-GUIDE${NC}"
echo -e "  ${CYAN}  → SSH : ssh pi@10.0.0.1${NC}"
echo ""
echo -e "  ${BOLD}${MAGENTA}🌐  ACCÈS SSH ADMIN (via modem — sans timer)${NC}"
if [ "${ETH_MODE_ONLY}" = false ]; then
    echo -e "  ${CYAN}  → SSH : ssh pi@${ETH_IP}${NC}            ${DIM}# IP DHCP actuelle${NC}"
fi
echo -e "  ${MAGENTA}sudo bash /usr/local/bin/sos-guide-debug-stop.sh${NC}     ${DIM}# Stopper debug SSH${NC}"
sep_bold
echo ""
echo -e "  ${BOLD}${GREEN}🚀  PRÊT POUR LA PRODUCTION !${NC}"
echo -e "  ${YELLOW}⚠   TEST : Connectez un smartphone au WiFi '${SSID}'${NC}"
echo -e "  ${YELLOW}⚠   Le portail doit s'ouvrir automatiquement${NC}"
echo -e "  ${YELLOW}⚠   Accès admin : http://${LOCAL_IP}/admin (identifiant admin)${NC}"
echo ""
sep_bold
echo -e "  ${DIM}Développé par Ludovic MARTIN — contact@sos-guide.fr${NC}"
sep_bold
echo ""
exit 0
