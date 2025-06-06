#!/bin/bash

# Fungsi untuk mendeteksi path direktori script Cacti
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
SOURCE_SCRIPT="$(dirname "$0")/graphnostek.sh"
TARGET_SCRIPT="$CACTI_SCRIPTS/graphonu.sh"

# Pastikan file sumber ada
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "❌ File sumber tidak ditemukan: $SOURCE_SCRIPT"
    exit 1
fi

# Salin file ke direktori Cacti
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

echo "✅ File berhasil disalin ke: $TARGET_SCRIPT"
echo "ℹ️  Sekarang Anda bisa menambahkan 'Input Method' secara manual via Web GUI Cacti:"
echo "    - Name: GraphONU Manual Input"
echo "    - Type: Script"
echo "    - Input/Output: Script/Script"
echo "    - Script Path: $TARGET_SCRIPT"
echo "    - Input Fields: hostname (isi nama perangkat)"
