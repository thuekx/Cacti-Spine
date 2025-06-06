#!/bin/bash

CONFIG_FILE="/var/www/html/cacti/scripts/graphonu_single.conf"
tmp_file="/tmp/graphonu_single.tmp"
log_file="/tmp/graphonu_single.log"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Konfigurasi tidak ditemukan. Jalankan setup terlebih dahulu." >&2
    exit 1
fi

source "$CONFIG_FILE"

if ! command -v expect >/dev/null 2>&1; then
    echo "❌ 'expect' belum terinstal. Jalankan: sudo apt install expect"
    exit 1
fi

/usr/bin/expect <<EOF > "$tmp_file"
spawn telnet $ip
expect "ogin:"
send "$user\r"
expect "assword:"
send "$pass\r"
expect "#"
send "[string tolower $mode] == \"ifconfig\" ? \"ifconfig $iface | grep bytes\" : \"wan show\"\r"
expect "#"
send "exit\r"
EOF

if [ "$mode" == "ifconfig" ]; then
    rx_bytes=$(grep "RX bytes" "$tmp_file" | awk -F'[: ]+' '{print $3}' | head -1)
    tx_bytes=$(grep "TX bytes" "$tmp_file" | awk -F'[: ]+' '{print $7}' | head -1)
else
    rx_bytes=$(awk -v ifname="$iface" '$0 ~ ifname && tolower($0) ~ /rx/ { match($0, /[0-9]+[ ]*bps/, a); print a[0] }' "$tmp_file" | grep -Eo '[0-9]+' | head -1)
    tx_bytes=$(awk -v ifname="$iface" '$0 ~ ifname && tolower($0) ~ /tx/ { match($0, /[0-9]+[ ]*bps/, a); print a[0] }' "$tmp_file" | grep -Eo '[0-9]+' | head -1)
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
