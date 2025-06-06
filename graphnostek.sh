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
if ! command -v expect >/dev/null 2>&1; then
    echo "❌ Program 'expect' belum terinstall. Jalankan: sudo apt install expect"
    exit 1
fi
CACTI_SCRIPTS=$(detect_cacti_script_path)
CONF_FILE="$CACTI_SCRIPTS/nostek_devices.conf"
TMP_DIR="/tmp"
LOG_DIR="/var/log/nostek"
mkdir -p "$LOG_DIR"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: File konfigurasi tidak tersedia. Jalankan nostek-setup.sh dulu."
    exit 1
fi
FILTER_NAME="$1"
while IFS="|" read -r name ip user pass mode ifname; do
    if [ -n "$FILTER_NAME" ] && [ "$FILTER_NAME" != "$name" ]; then
        continue
    fi
    tmp_file="$TMP_DIR/nostekspeed_${name}.tmp"
    log_file="$LOG_DIR/nostekspeed_${name}.log"
    # Jalankan expect untuk telnet
    /usr/bin/expect <<EOF > "$tmp_file"
spawn telnet $ip
expect "Login:"
send "$user\r"
expect "Password:"
send "$pass\r"
expect "#"
send "[string tolower $mode] == \"ifconfig\" ? \"ifconfig $ifname | grep bytes\" : \"wan show\"\r"
expect "#"
send "exit\r"
EOF
    echo "[$(date '+%F %T')] Output dari $name ($ip)" >> "$log_file"
    cat "$tmp_file" >> "$log_file"
    echo -e "\n----------------------------\n" >> "$log_file"

    if [ "$mode" == "ifconfig" ]; then
        rx_bytes=$(grep "RX bytes" "$tmp_file" | awk -F'[: ]+' '{print $3}' | head -1)
        tx_bytes=$(grep "TX bytes" "$tmp_file" | awk -F'[: ]+' '{print $7}' | head -1)
    else
        rx_bytes=$(awk -v ifname="$ifname" '$0 ~ ifname && tolower($0) ~ /rx/ { match($0, /[0-9]+[ ]*bps/, a); print a[0] }' "$tmp_file" | grep -Eo '[0-9]+' | head -1)
        tx_bytes=$(awk -v ifname="$ifname" '$0 ~ ifname && tolower($0) ~ /tx/ { match($0, /[0-9]+[ ]*bps/, a); print a[0] }' "$tmp_file" | grep -Eo '[0-9]+' | head -n1)
    fi

    rx_bytes=${rx_bytes:-0}
    tx_bytes=${tx_bytes:-0}

    echo "$rx_bytes $tx_bytes" >> "$log_file"

    if [ "$(wc -l < "$log_file")" -ge 2 ]; then
        R2=$(head -1 "$log_file" | awk '{print $1}')
        T2=$(head -1 "$log_file" | awk '{print $2}')
        R1=$(tail -1 "$log_file" | awk '{print $1}')
        T1=$(tail -1 "$log_file" | awk '{print $2}')
        TBPS=$(( (T2 - T1) / 300 ))
        RBPS=$(( (R2 - R1) / 300 ))
        [ "$TBPS" -ge 1250000 ] && TBPS=0
        [ "$RBPS" -ge 1250000 ] && RBPS=0
        echo "tx:$TBPS"
        echo "rx:$RBPS"
    else
        echo "tx:0"
        echo "rx:0"
    fi
done < "$CONF_FILE"
