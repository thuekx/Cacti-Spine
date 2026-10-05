#!/bin/bash
# Script Data Input Cacti: ambil trafik WAN modem/ONU lewat telnet.
#
# Pemakaian : graphnostek.sh <nama_perangkat>
# Output    : tx:<bit/s> rx:<bit/s>   (U = tidak ada data)
# Konfigurasi perangkat dibuat oleh nostek-setup.sh.

CONF_FILE=${NOSTEK_CONF:-/etc/cacti-nostek/devices.conf}
STATE_DIR=${NOSTEK_STATE:-/var/tmp/cacti-nostek}
export NOSTEK_TIMEOUT=${NOSTEK_TIMEOUT:-10}

fail() {
    echo "ERROR: $*" >&2
    echo "tx:U rx:U"
    exit 0
}

name=$1
[ -n "$name" ] || { echo "Pemakaian: $0 <nama_perangkat>" >&2; exit 1; }

# Kompatibilitas: lokasi konfigurasi lama di direktori scripts Cacti
if [ ! -f "$CONF_FILE" ] && [ -f "$(dirname "$0")/nostek_devices.conf" ]; then
    CONF_FILE="$(dirname "$0")/nostek_devices.conf"
fi

command -v expect >/dev/null 2>&1 || fail "'expect' belum terinstal (sudo apt install expect telnet)"
[ -r "$CONF_FILE" ] || fail "konfigurasi $CONF_FILE tidak bisa dibaca, jalankan nostek-setup.sh"

line=$(awk -F'|' -v n="$name" '$1 == n { print; exit }' "$CONF_FILE")
[ -n "$line" ] || fail "perangkat '$name' tidak ada di $CONF_FILE"
IFS='|' read -r _ ip user pass mode ifname <<< "$line"

case "$mode" in
    ifconfig) cmd="ifconfig $ifname" ;;
    wan)      cmd="wan show" ;;
    *)        fail "mode '$mode' tidak dikenal (wan/ifconfig)" ;;
esac

# Kredensial dikirim lewat environment agar karakter khusus aman di Tcl
output=$(NOSTEK_IP="$ip" NOSTEK_USER="$user" NOSTEK_PASS="$pass" NOSTEK_CMD="$cmd" \
    expect 2>/dev/null <<'EOF'
set timeout $env(NOSTEK_TIMEOUT)
log_user 1
spawn telnet $env(NOSTEK_IP)
expect {
    -re "ogin:|sername:" {}
    timeout { exit 2 }
    eof     { exit 2 }
}
send -- "$env(NOSTEK_USER)\r"
expect {
    "assword:" {}
    timeout { exit 2 }
}
send -- "$env(NOSTEK_PASS)\r"
expect {
    -re {[#>$] ?$} {}
    timeout { exit 3 }
}
send -- "$env(NOSTEK_CMD)\r"
expect {
    -re {[#>$] ?$} {}
    timeout { exit 4 }
}
send -- "exit\r"
expect eof
EOF
)
rc=$?
output=$(printf '%s\n' "$output" | tr -d '\r')

mkdir -p "$STATE_DIR" 2>/dev/null
safe_name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
[ -n "$NOSTEK_DEBUG" ] && printf '%s\n' "$output" > "$STATE_DIR/$safe_name.last"

[ "$rc" -eq 0 ] || fail "telnet/login ke $name ($ip) gagal (kode $rc)"

if [ "$mode" = "ifconfig" ]; then
    # Format busybox "RX bytes:123" maupun net-tools baru "RX packets 1  bytes 123"
    rx_bytes=$(printf '%s\n' "$output" | grep -oE 'RX (packets [0-9]+ +)?bytes:? *[0-9]+' | grep -oE '[0-9]+$' | head -n 1)
    tx_bytes=$(printf '%s\n' "$output" | grep -oE 'TX (packets [0-9]+ +)?bytes:? *[0-9]+' | grep -oE '[0-9]+$' | head -n 1)
    if [ -z "$rx_bytes" ] || [ -z "$tx_bytes" ]; then
        fail "counter RX/TX tidak ditemukan di output '$cmd'"
    fi

    now=$(date +%s)
    state_file="$STATE_DIR/$safe_name.state"
    prev=$(cat "$state_file" 2>/dev/null)
    echo "$now $rx_bytes $tx_bytes" > "$state_file"

    read -r t1 r1 x1 <<< "$prev"
    if [ -z "$t1" ] || [ "$now" -le "$t1" ] || [ "$rx_bytes" -lt "$r1" ] || [ "$tx_bytes" -lt "$x1" ]; then
        # Sampel pertama atau counter reset (modem reboot)
        echo "tx:U rx:U"
        exit 0
    fi
    elapsed=$(( now - t1 ))
    echo "tx:$(( (tx_bytes - x1) * 8 / elapsed )) rx:$(( (rx_bytes - r1) * 8 / elapsed ))"
else
    # "wan show" sudah menampilkan kecepatan (bps)
    rx=$(printf '%s\n' "$output" | grep -F -- "$ifname" | grep -i 'rx' | grep -oE '[0-9]+ *bps' | grep -oE '[0-9]+' | head -n 1)
    tx=$(printf '%s\n' "$output" | grep -F -- "$ifname" | grep -i 'tx' | grep -oE '[0-9]+ *bps' | grep -oE '[0-9]+' | head -n 1)
    echo "tx:${tx:-U} rx:${rx:-U}"
fi
