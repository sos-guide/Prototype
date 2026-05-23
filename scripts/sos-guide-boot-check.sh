#!/bin/bash
WFACE="wlan0"
EFACE="eth0"

if [ -f /root/integrity.hash ]; then
    if ! sha256sum -c /root/integrity.hash >/dev/null 2>&1; then
        logger "SOS-GUIDE: INTEGRITE COMPROMISE - SHUTDOWN"
        poweroff
    fi
fi
if ! iptables -C FORWARD -i ${WFACE} -o ${EFACE} -j DROP 2>/dev/null; then
    logger "SOS-GUIDE: CRITIQUE - Isolation Internet COMPROMISE"
    iptables -P FORWARD DROP
    iptables -A FORWARD -i ${WFACE} -o ${WFACE} -j DROP
    iptables -A FORWARD -i ${WFACE} -o ${EFACE} -j DROP
    iptables -A FORWARD -i ${WFACE} -j DROP
    logger "SOS-GUIDE: Regles isolation RESTAUREES"
fi
if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "MASQUERADE\|SNAT"; then
    logger "SOS-GUIDE: ALERTE - Regle NAT sortante detectee (SUPPRIMEE)"
    iptables -t nat -F POSTROUTING
fi
