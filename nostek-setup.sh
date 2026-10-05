#!/bin/bash
# Setup grafik trafik modem/ONU (Nostek dan sejenisnya) untuk Cacti.
# - Menginstal expect + telnet
# - Menyimpan daftar perangkat ke /etc/cacti-nostek/devices.conf
# - Menyalin graphnostek.sh ke direktori scripts Cacti
# Pemakaian: sudo ./nostek-setup.sh
set -euo pipefail

CONF_DIR="/etc/cacti-nostek"
CONF_FILE="$CONF_DIR/devices.conf"
SOURCE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphnostek.sh"

die() { echo "❌ $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root: sudo $0"
[[ -f "$SOURCE_SCRIPT" ]] || die "File $SOURCE_SCRIPT tidak ditemukan."

# ========================
# Paket
# ========================
if ! command -v expect >/dev/null 2>&1 || ! command -v telnet >/dev/null 2>&1; then
    echo "🔧 Menginstal expect dan telnet..."
    apt-get update && apt-get install -y expect telnet
fi

# ========================
# Direktori scripts Cacti
# ========================
CACTI_SCRIPTS=""
for path in /var/www/html/cacti/scripts /usr/share/cacti/site/scripts /usr/share/cacti/scripts /opt/cacti/scripts; do
    if [[ -d "$path" ]]; then CACTI_SCRIPTS="$path"; break; fi
done
if [[ -z "$CACTI_SCRIPTS" ]]; then
    read -rp "Path direktori scripts Cacti: " CACTI_SCRIPTS
    [[ -d "$CACTI_SCRIPTS" ]] || die "Direktori tidak valid."
fi
echo "📂 Direktori scripts Cacti: $CACTI_SCRIPTS"

# ========================
# Daftar perangkat
# ========================
mkdir -p "$CONF_DIR"
LEGACY_CONF="$CACTI_SCRIPTS/nostek_devices.conf"

if [[ -s "$CONF_FILE" ]]; then
    echo "Konfigurasi sudah ada ($(wc -l < "$CONF_FILE") perangkat)."
    read -rp "Tambah ke daftar yang ada (t) atau buat ulang (b)? [t/b]: " pilih
    [[ "$pilih" =~ ^[Bb]$ ]] && : > "$CONF_FILE"
elif [[ -s "$LEGACY_CONF" ]]; then
    read -rp "Ditemukan konfigurasi lama $LEGACY_CONF. Pindahkan ke $CONF_FILE? (Y/n): " pindah
    if [[ ! "$pindah" =~ ^[Nn]$ ]]; then
        cp "$LEGACY_CONF" "$CONF_FILE"
        rm -f "$LEGACY_CONF"
        echo "✅ Dipindahkan."
    fi
fi
touch "$CONF_FILE"

read -rp "Tambah perangkat sekarang? (Y/n): " tambah
while [[ ! "$tambah" =~ ^[Nn]$ ]]; do
    read -rp "Nama perangkat (huruf/angka/._-, misal ONU-ZTE1): " name
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Nama tidak valid."; continue
    fi
    if awk -F'|' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$CONF_FILE"; then
        echo "Nama '$name' sudah dipakai."; continue
    fi
    read -rp "IP address: " ip
    read -rp "Username telnet: " user
    read -rsp "Password telnet: " pass; echo
    read -rp "Mode [wan/ifconfig]: " mode
    read -rp "Interface WAN (misal ppp0 atau 1_INTERNET_R_VID_100): " ifname

    if [[ "$mode" != "wan" && "$mode" != "ifconfig" ]]; then
        echo "Mode harus 'wan' atau 'ifconfig'."; continue
    fi
    if [[ "$ip$user$pass$ifname" == *"|"* ]]; then
        echo "Karakter '|' tidak boleh dipakai."; continue
    fi

    echo "$name|$ip|$user|$pass|$mode|$ifname" >> "$CONF_FILE"
    echo "✅ $name ditambahkan."
    read -rp "Tambah perangkat lain? (y/N): " lagi
    [[ "$lagi" =~ ^[Yy]$ ]] || break
done

# Berisi password: hanya root dan www-data (poller) yang boleh membaca
chown root:www-data "$CONF_DIR" "$CONF_FILE"
chmod 750 "$CONF_DIR"
chmod 640 "$CONF_FILE"

# ========================
# Pasang script poller
# ========================
TARGET_SCRIPT="$CACTI_SCRIPTS/graphnostek.sh"
install -m 755 "$SOURCE_SCRIPT" "$TARGET_SCRIPT"

echo ""
echo "📦 Selesai. Total perangkat: $(wc -l < "$CONF_FILE")"
echo "✅ Script terpasang: $TARGET_SCRIPT"
echo ""
echo "Uji manual (jalankan 2x berjarak 1 menit untuk mode ifconfig):"
echo "    sudo -u www-data $TARGET_SCRIPT <nama_perangkat>"
echo ""
echo "Buat Data Input Method di Cacti (Console > Data Collection > Data Input Methods):"
echo "    Input Type   : Script/Command"
echo "    Input String : <path_cacti>/scripts/graphnostek.sh <name>"
echo "    Input Fields : name"
echo "    Output Fields: tx, rx  (satuan bit/s, Data Source Type GAUGE)"
