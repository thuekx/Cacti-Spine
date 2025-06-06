#!/bin/bash

detect_cacti_script_path() {
    possible_paths=(
        "/var/www/html/cacti/scripts"
        "/usr/share/cacti/scripts"
        "/var/lib/cacti/scripts"
        "/opt/cacti/scripts"
    )
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && [ -w "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    echo "❌ Tidak bisa mendeteksi path direktori script Cacti."
    read -rp "Masukkan path manual ke direktori script Cacti: " manual_path
    if [ ! -d "$manual_path" ]; then
        echo "🚫 Path tidak valid. Keluar."
        exit 1
    fi
    echo "$manual_path"
}

CACTI_SCRIPTS=$(detect_cacti_script_path)
CONF_FILE="$CACTI_SCRIPTS/nostek_devices.conf"
mkdir -p "$(dirname "$CONF_FILE")"

echo "=== NOSTEK SETUP (MULTI DEVICE) ==="
echo "File konfigurasi: $CONF_FILE"
echo "-----------------------------------"
> "$CONF_FILE"

while true; do
    read -rp "Nama perangkat (misal: ONU-ZTE1): " nostek_name
    read -rp "IP address perangkat: " nostek_host
    read -rp "Username Telnet: " nostek_user
    read -rsp "Password Telnet: " nostek_pass
    echo

    echo "$nostek_name|$nostek_host|$nostek_user|$nostek_pass" >> "$CONF_FILE"
    echo "✅ Perangkat $nostek_name ditambahkan."

    read -rp "Tambah perangkat lain? (y/n): " tambah
    [[ "$tambah" =~ ^[Yy]$ ]] || break
done

echo "📦 Konfigurasi selesai. Total perangkat: $(wc -l < "$CONF_FILE")"
