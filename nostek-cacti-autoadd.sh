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
CACTI_CLI="/var/www/html/cacti/cli"
CONF_FILE="$CACTI_SCRIPTS/nostek_devices.conf"
DATA_INPUT_NAME="GraphNostek Device Monitor"

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: File konfigurasi tidak ditemukan!"
    exit 1
fi

php "$CACTI_CLI/add_data_input.php" --name="$DATA_INPUT_NAME"     --type=script     --input-output=1     --script-path="$CACTI_SCRIPTS/graphnostek.sh"     --arg-format=hostname

input_id=$(php "$CACTI_CLI/add_data_input.php" --list | grep "$DATA_INPUT_NAME" | awk '{print $1}')
if [ -z "$input_id" ]; then
    echo "❌ Gagal mendapatkan ID input method!"
    exit 1
fi

while IFS="|" read -r name ip user pass; do
    device_script="$CACTI_SCRIPTS/graphnostek-$name.sh"

    cat > "$device_script" <<EOF
#!/bin/bash
exec /bin/bash "$CACTI_SCRIPTS/graphnostek.sh" "$name"
EOF
    chmod +x "$device_script"

    php "$CACTI_CLI/add_data_source.php"         --name="nostek-$name"         --host-id=1         --data-input-id=$input_id         --data-input-path="$device_script"         --arg-value="$name"

    echo "✅ Device $name berhasil ditambahkan ke Cacti."
done < "$CONF_FILE"
