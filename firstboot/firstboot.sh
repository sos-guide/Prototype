#!/bin/bash
# SOS-GUIDE First Boot – Mode STARTER (corrigé)

set -e

WEB_DIR="/var/www/sos-guide"
STARTER_HTML="/var/www/sos-guide/starter.html"
API_PHP="/var/www/sos-guide/api_install.php"
CONFIG_JSON="/var/www/sos-guide/data/config.json"

# Arrêter les services existants (au cas où)
systemctl stop hostapd dnsmasq nginx 2>/dev/null || true

# --- Configuration hostapd (réseau ouvert STARTER) ---
cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=⛑️ SOS-GUIDE - STARTER
hw_mode=g
channel=6
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=0
country_code=FR
ieee80211d=1
ieee80211n=1
EOF

# --- Configuration dnsmasq (DHCP + DNS captif) ---
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=10.0.0.100,10.0.0.200,1h
dhcp-option=3,10.0.0.1
dhcp-option=6,10.0.0.1
address=/#/10.0.0.1
EOF

# --- Configuration Nginx pour le portail captif STARTER ---
cat > /etc/nginx/sites-available/sos-guide <<'NGINXEOF'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/sos-guide;
    index starter.html;

    location = /hotspot-detect.html       { return 302 http://10.0.0.1/; }
    location = /library/test/success.html { return 302 http://10.0.0.1/; }
    location = /generate_204              { return 302 http://10.0.0.1/; }
    location = /gen_204                   { return 302 http://10.0.0.1/; }
    location = /connecttest.txt           { return 302 http://10.0.0.1/; }
    location = /ncsi.txt                  { return 302 http://10.0.0.1/; }
    location = /success.txt               { return 302 http://10.0.0.1/; }

    location /api/install {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/phpPHP_VERSION-fpm.sock;
    }

    location / {
        try_files $uri $uri/ /starter.html;
    }

    location ~ /\. { deny all; }
    location ~* \.(env|ini|log|sh|sql|conf|cfg)$ { deny all; }
}
NGINXEOF

# Détection dynamique de la version PHP
PHP_VERSION=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
[ -z "$PHP_VERSION" ] && PHP_VERSION="8.2"
sed -i "s|phpPHP_VERSION|php${PHP_VERSION}|g" /etc/nginx/sites-available/sos-guide

ln -sf /etc/nginx/sites-available/sos-guide /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# --- Copier les fichiers firstboot depuis le dépôt (monté dans /boot/firmware/firstboot ou /boot/firstboot)
mkdir -p "$WEB_DIR"
if [ -f "/boot/firmware/firstboot/starter.html" ]; then
    cp /boot/firmware/firstboot/starter.html "$WEB_DIR/"
    cp /boot/firmware/firstboot/api_install.php "$WEB_DIR/"
elif [ -f "/boot/firstboot/starter.html" ]; then
    cp /boot/firstboot/starter.html "$WEB_DIR/"
    cp /boot/firstboot/api_install.php "$WEB_DIR/"
else
    echo "Fichiers firstboot introuvables !" >&2
    exit 1
fi

chown www-data:www-data "$WEB_DIR/starter.html" "$WEB_DIR/api_install.php"
chmod 644 "$WEB_DIR/starter.html" "$WEB_DIR/api_install.php"

# --- Activer et démarrer les services ---
systemctl unmask hostapd dnsmasq nginx 2>/dev/null || true
systemctl enable hostapd dnsmasq nginx php${PHP_VERSION}-fpm
systemctl restart hostapd dnsmasq nginx php${PHP_VERSION}-fpm

# --- Créer le fichier de configuration vide s'il n'existe pas ---
mkdir -p "$(dirname "$CONFIG_JSON")"
if [ ! -f "$CONFIG_JSON" ]; then
    echo '{"establishment":{},"reassurance":{"message":""}}' > "$CONFIG_JSON"
    chown www-data:www-data "$CONFIG_JSON"
fi

# --- Marquer que le firstboot a été exécuté ---
mkdir -p /var/lib/sos-guide
touch /var/lib/sos-guide/firstboot-done

# --- Désactiver ce service après exécution ---
systemctl disable sos-guide-firstboot.service 2>/dev/null || true

exit 0
