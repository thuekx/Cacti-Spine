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
LOG_DIR="/var/log/nostek"
TMP_DIR="/tmp"

mkdir -p "$LOG_DIR"

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Konfigurasi belum tersedia. Jalankan nostek-setup.sh dulu." >&2
    exit 1
fi

FILTER_NAME="$1"

run_telnet() {
    local name="$1"
    local ip="$2"
    local user="$3"
    local pass="$4"

    local log_file="$LOG_DIR/nostekspeed_${name}.log"
    local tmp_file="$TMP_DIR/nostekspeed_${name}.tmp"

    /usr/bin/expect <<EOF > "$tmp_file"
spawn telnet $ip
expect "Login:"
send "$user\r"
expect "Password:"
send "$pass\r"
expect "#"
send "wan show\r"
expect "#"
send "exit\r"
EOF

    echo "[$(date '+%F %T')] Log $name ($ip)" >> "$log_file"
    cat "$tmp_file" >> "$log_file"
    echo -e "\n----------------------------\n" >> "$log_file"

    echo "✅ Data dari $name disimpan di $tmp_file dan $log_file"
}

while IFS="|" read -r name ip user pass; do
    if [ -n "$FILTER_NAME" ] && [ "$FILTER_NAME" != "$name" ]; then
        continue
    fi
    run_telnet "$name" "$ip" "$user" "$pass"
done < "$CONF_FILE"
