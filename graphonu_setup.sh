#!/bin/bash

CONFIG_FILE="/var/www/html/cacti/scripts/graphonu_single.conf"
mkdir -p "$(dirname "$CONFIG_FILE")"

echo "=== Setup GraphONU Single Device ==="
read -rp "IP Address perangkat: " ip
read -rp "Username Telnet: " user
read -rsp "Password Telnet: " pass
echo
read -rp "Mode (wan / ifconfig): " mode
read -rp "Interface (contoh: ppp0 atau 1_INTERNET_R_VID_100): " iface

cat > "$CONFIG_FILE" <<EOF
ip="$ip"
user="$user"
pass="$pass"
mode="$mode"
iface="$iface"
EOF

chmod 600 "$CONFIG_FILE"
echo "✅ Konfigurasi disimpan di $CONFIG_FILE"
