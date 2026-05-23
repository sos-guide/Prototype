#!/bin/bash
# SOS-GUIDE – Finalisation de l'installation (mode STARTER → PRODUCTION)
# Ce script applique TOUTES les configurations de sécurité de install.sh

set -e

CONFIG_FILE="/var/www/sos-guide/data/config.json"
[ ! -f "$CONFIG_FILE" ] && { echo "Erreur : config.json introuvable."; exit 1; }

# Installer jq si absent
if ! command -v jq &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq jq
fi

# Lire les valeurs
NODE_NAME=$(jq -r '.establishment.name // "SOS-GUIDE"' "$CONFIG_FILE")
WIFI_PASSWORD=$(jq -r '.wifiPassword // ""' "$CONFIG_FILE")
ENABLE_LORA=$(jq -r '.enableLoRa // false' "$CONFIG_FILE")
ENABLE_ETHERNET=$(jq -r '.enableEthernet // false' "$CONFIG_FILE")
WIFI_IFACE=$(iw dev | awk '$1=="Interface"{print $2; exit}')
ETH_IFACE=$(ip -o link show | awk -F': ' '/^[0-9]+: (en|eth)/{print $2; exit}')
[ -z "$ETH_IFACE" ] && ETH_IFACE="eth0"

LOCAL_IP="10.0.0.1"
SSID="⛑️ SOS-GUIDE - $NODE_NAME"

# Arrêter les services temporaires
systemctl stop hostapd dnsmasq nginx

# --- Configuration définitive de hostapd ---
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
EOF

if [ -n "$WIFI_PASSWORD" ] && [ ${#WIFI_PASSWORD} -ge 8 ]; then
    cat >> /etc/hostapd/hostapd.conf <<EOF
wpa=2
wpa_passphrase=$WIFI_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
else
    echo "wpa=0" >> /etc/hostapd/hostapd.conf
fi

# --- Configuration dnsmasq complète ---
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

# --- Configuration réseau systemd-networkd ---
cat > /etc/systemd/network/20-wlan-ap.network <<EOF
[Match]
Name=${WIFI_IFACE}

[Network]
Address=${LOCAL_IP}/24
IPv6AcceptRA=no
IPv6LinkLocalAddressGenerationMode=none
IPv6Disable=1

[Link]
WakeOnLan=off

[WLAN]
PowerSave=off
EOF

if [ "$ENABLE_ETHERNET" = "true" ]; then
    cat > /etc/systemd/network/10-${ETH_IFACE}.network <<EOF
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
    systemctl enable systemd-networkd
fi

# --- Firewall iptables complet (identique à install.sh) ---
iptables -F
iptables -t nat -F
iptables -t mangle -F

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

if [ "$ENABLE_ETHERNET" = "true" ]; then
    iptables -A INPUT -i ${ETH_IFACE} -p tcp --dport 22 -m conntrack --ctstate NEW \
        -m limit --limit 3/min --limit-burst 3 -j ACCEPT
fi

iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 80 \
    -m limit --limit 30/second --limit-burst 200 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 443 \
    -m limit --limit 30/second --limit-burst 200 -j ACCEPT

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT -i ${WIFI_IFACE} -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i ${WIFI_IFACE} -p tcp --dport 53 -j ACCEPT

iptables -A INPUT -i ${WIFI_IFACE} -j DROP

iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 80 -j DNAT --to-destination ${LOCAL_IP}:80
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 443 -j DNAT --to-destination ${LOCAL_IP}:443
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p udp --dport 53 -j DNAT --to-destination ${LOCAL_IP}:53
iptables -t nat -A PREROUTING -i ${WIFI_IFACE} -p tcp --dport 53 -j DNAT --to-destination ${LOCAL_IP}:53

iptables -A FORWARD -i ${WIFI_IFACE} -o ${WIFI_IFACE} -j DROP
iptables -A FORWARD -i ${WIFI_IFACE} -o ${ETH_IFACE} -j DROP
iptables -A FORWARD -i ${WIFI_IFACE} -j DROP

mkdir -p /etc/iptables
netfilter-persistent save

# --- Verrouillage et intégrité ---
WEB_DIR="/var/www/sos-guide"
chown -R www-data:www-data "$WEB_DIR"
chmod -R a-w "$WEB_DIR"
if command -v chattr &>/dev/null; then
    find "$WEB_DIR" -type f ! -path "$WEB_DIR/data/*" -exec chattr +i {} \;
    chattr -R -i "$WEB_DIR/data/"
fi
find "$WEB_DIR" -type f -exec sha256sum {} \; > /root/integrity.hash
sha256sum /etc/nginx/sites-available/sos-guide >> /root/integrity.hash

# --- Services optionnels ---
if [ "$ENABLE_LORA" = "true" ]; then
    systemctl enable lora-service 2>/dev/null || true
    systemctl start lora-service 2>/dev/null || true
fi

# --- Désactiver le service firstboot ---
systemctl disable sos-guide-firstboot.service
rm -f /etc/systemd/system/sos-guide-firstboot.service
systemctl daemon-reload

# --- Marquer l'installation comme terminée ---
mkdir -p /var/lib/sos-guide
echo "$(date) - Installation finalisée" > /var/lib/sos-guide/installed

# --- Redémarrer tous les services ---
systemctl restart systemd-networkd hostapd dnsmasq nginx

# Redémarrer le système
reboot
