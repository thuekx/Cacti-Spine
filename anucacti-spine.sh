#!/bin/bash
# Installer otomatis Cacti + Spine untuk Ubuntu Server 24.04
# Pemakaian: sudo ./anucacti-spine.sh
set -euo pipefail

INSTALL_DIR="/var/www/html/cacti"
SPINE_DIR="/usr/local/spine"
SPINE_BIN="$SPINE_DIR/bin/spine"
SPINE_CONF="$SPINE_DIR/etc/spine.conf"
MARIADB_CONF="/etc/mysql/mariadb.conf.d/99-cacti.cnf"  # 99- agar tidak tertimpa 50-server.cnf
export DEBIAN_FRONTEND=noninteractive

die() { echo "❌ $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root: sudo $0"
grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null \
    || echo "⚠️  Skrip ini diuji di Ubuntu 24.04. OS lain mungkin tidak cocok."

WORK_DIR=$(mktemp -d /tmp/cacti-install.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# ========================
# INPUT
# ========================
echo "📋 Konfigurasi instalasi Cacti"

read -rp "🌐 Domain (FQDN), contoh cacti.example.com: " FQDN
[[ "$FQDN" =~ ^[A-Za-z0-9.-]+$ ]] || die "FQDN tidak valid."

while true; do
    read -rsp "🔐 Password database cactiuser: " PASSWORD; echo
    read -rsp "🔐 Ulangi password: " PASSWORD2; echo
    if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
        echo "Password tidak sama, ulangi."
    elif [[ ! "$PASSWORD" =~ ^[A-Za-z0-9._@%+=,!-]{8,}$ ]]; then
        echo "Minimal 8 karakter; hanya huruf, angka, dan . _ @ % + = , ! -"
    else
        break
    fi
done

DEFAULT_TZ=$(cat /etc/timezone 2>/dev/null || true)
DEFAULT_TZ=${DEFAULT_TZ:-Asia/Jakarta}
read -rp "🕒 Timezone [$DEFAULT_TZ]: " TIMEZONE
TIMEZONE=${TIMEZONE:-$DEFAULT_TZ}
if [[ -d /usr/share/zoneinfo && ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    die "Timezone '$TIMEZONE' tidak dikenal."
fi

# ========================
# CLEANUP (opsional)
# ========================
echo ""
echo "⚠️  Opsi fresh install: MENGHAPUS Apache, PHP, MariaDB beserta semua database"
echo "    dan seluruh isi /var/www/html. Pilih N untuk lanjut tanpa menghapus apa pun."
read -rp "Hapus instalasi lama dulu? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🧹 Membersihkan sistem..."
    systemctl stop apache2 mariadb 2>/dev/null || true
    apt-get purge -y 'apache2*' 'php*' 'mysql*' 'mariadb*' 'libapache2-mod-php*'
    apt-get autoremove -y
    rm -rf /etc/apache2 /etc/mysql /etc/php /var/lib/mysql /var/www/html/* \
           /var/log/apache2 /var/log/mysql /etc/systemd/system/mariadb.service.d \
           "$SPINE_DIR" /etc/cron.d/cacti
    echo "✅ Pembersihan selesai."
fi

[[ -e "$INSTALL_DIR" ]] && die "$INSTALL_DIR sudah ada. Hapus dulu atau pilih 'y' pada opsi fresh install."

# ========================
# STEP 1: Paket
# ========================
echo "🔧 Menginstal paket..."
apt-get update
apt-get install -y \
    apache2 mariadb-server mariadb-client \
    php libapache2-mod-php php-cli php-common php-mysql php-snmp php-gd php-xml \
    php-mbstring php-curl php-ldap php-gmp php-intl php-bcmath php-zip \
    snmp snmpd rrdtool git curl ca-certificates tzdata \
    build-essential autoconf automake libtool pkg-config help2man \
    libssl-dev libmariadb-dev libsnmp-dev
systemctl enable --now mariadb apache2
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Timezone '$TIMEZONE' tidak dikenal."

# ========================
# STEP 2: Hostname
# ========================
hostnamectl set-hostname "$FQDN" || echo "⚠️  Gagal set hostname, dilewati."

# ========================
# STEP 3: Tuning MariaDB (sebelum database dibuat)
# ========================
echo "🛠  Menulis $MARIADB_CONF ..."
MEM_MB=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1024 ))
POOL_MB=$(( MEM_MB / 4 ))           # 25% RAM, sesuai rekomendasi Cacti
(( POOL_MB < 128 )) && POOL_MB=128
HEAP_MB=$(( MEM_MB / 50 ))          # 2% RAM
(( HEAP_MB < 64 )) && HEAP_MB=64

cat > "$MARIADB_CONF" <<EOF
# Dibuat oleh anucacti-spine.sh (RAM terdeteksi: ${MEM_MB} MB)
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_connections = 200
max_allowed_packet = 16M
max_heap_table_size = ${HEAP_MB}M
tmp_table_size = ${HEAP_MB}M
join_buffer_size = 1M
sort_buffer_size = 1M
innodb_file_per_table = ON
innodb_buffer_pool_size = ${POOL_MB}M
innodb_doublewrite = OFF
innodb_use_atomic_writes = ON
innodb_flush_log_at_timeout = 3
innodb_read_io_threads = 32
innodb_write_io_threads = 16
innodb_io_capacity = 5000
innodb_io_capacity_max = 10000

[client]
default-character-set = utf8mb4
EOF
chmod 644 "$MARIADB_CONF"
systemctl restart mariadb

# ========================
# STEP 4: Database
# ========================
echo "🗃️  Menyiapkan database..."
mysql -e "
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS cacti DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
ALTER USER 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON cacti.* TO 'cactiuser'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'cactiuser'@'localhost';
FLUSH PRIVILEGES;"

TABLES=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='cacti'")
[[ "$TABLES" -eq 0 ]] || die "Database 'cacti' sudah berisi tabel. Pilih 'y' pada opsi fresh install."

mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | mysql mysql

# ========================
# STEP 5: PHP
# ========================
echo "🐘 Mengatur php.ini (timezone, memory_limit, max_execution_time)..."
for ini in /etc/php/*/apache2/php.ini /etc/php/*/cli/php.ini; do
    [[ -f "$ini" ]] || continue
    sed -i -E \
        -e "s|^;?date\.timezone\s*=.*|date.timezone = $TIMEZONE|" \
        -e "s|^;?memory_limit\s*=.*|memory_limit = 512M|" \
        -e "s|^;?max_execution_time\s*=.*|max_execution_time = 60|" \
        "$ini"
done
timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true

# ========================
# STEP 6: Unduh Cacti (rilis stabil terbaru)
# ========================
latest_release() {
    git ls-remote --tags --refs "$1" 'release/*' \
        | sed 's#.*refs/tags/##' \
        | grep -E '^release/[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -n 1 || true
}

CACTI_TAG=${CACTI_VERSION:+release/$CACTI_VERSION}
CACTI_TAG=${CACTI_TAG:-$(latest_release https://github.com/Cacti/cacti.git)}
[[ -n "$CACTI_TAG" ]] || die "Tidak bisa menentukan versi Cacti terbaru (cek koneksi ke github.com)."
echo "⬇️  Mengunduh Cacti ${CACTI_TAG#release/}..."
git clone -q --depth 1 --branch "$CACTI_TAG" https://github.com/Cacti/cacti.git "$WORK_DIR/cacti"
rm -rf "$WORK_DIR/cacti/.git"
mv "$WORK_DIR/cacti" "$INSTALL_DIR"

mysql cacti < "$INSTALL_DIR/cacti.sql"

# ========================
# STEP 7: config.php
# ========================
CONFIG_PHP="$INSTALL_DIR/include/config.php"
cp "$INSTALL_DIR/include/config.php.dist" "$CONFIG_PHP"
sed -i \
    -e "s|^\$database_password = .*|\$database_password = '$PASSWORD';|" \
    -e "s|^\$url_path = .*|\$url_path = '/';|" \
    "$CONFIG_PHP"
chown -R www-data:www-data "$INSTALL_DIR"
chmod 640 "$CONFIG_PHP"

# ========================
# STEP 8: Apache (Cacti di root domain)
# ========================
cat > /etc/apache2/sites-available/cacti.conf <<EOF
<VirtualHost *:80>
    ServerName $FQDN
    DocumentRoot $INSTALL_DIR

    <Directory $INSTALL_DIR/>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    DirectoryIndex index.php index.html
    ErrorLog \${APACHE_LOG_DIR}/cacti_error.log
    CustomLog \${APACHE_LOG_DIR}/cacti_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf >/dev/null || true
a2ensite cacti >/dev/null
a2enmod rewrite >/dev/null
apachectl configtest
systemctl restart apache2

# ========================
# STEP 9: Cron poller
# ========================
echo "*/5 * * * * www-data /usr/bin/php $INSTALL_DIR/poller.php > /dev/null 2>&1" > /etc/cron.d/cacti
chmod 644 /etc/cron.d/cacti

# ========================
# STEP 10: Build Spine (versi sama dengan Cacti)
# ========================
echo "🐛 Build Spine..."
SPINE_TAG=$CACTI_TAG
if ! git ls-remote --exit-code --tags https://github.com/Cacti/spine.git "$SPINE_TAG" >/dev/null; then
    SPINE_TAG=$(latest_release https://github.com/Cacti/spine.git)
    echo "⚠️  Spine $CACTI_TAG tidak ada, memakai $SPINE_TAG"
fi
git clone -q --depth 1 --branch "$SPINE_TAG" https://github.com/Cacti/spine.git "$WORK_DIR/spine"
cd "$WORK_DIR/spine"

# Patch TINY_BUFSIZE (default 16) menjadi 64
TINY_FILE=$(grep -rl --include='*.h' '#define TINY_BUFSIZE' . | head -n 1 || true)
if [[ -n "$TINY_FILE" ]]; then
    sed -i 's/#define TINY_BUFSIZE.*/#define TINY_BUFSIZE 64/' "$TINY_FILE"
    echo "✅ TINY_BUFSIZE di-patch ($TINY_FILE)"
else
    echo "⚠️  Definisi TINY_BUFSIZE tidak ditemukan, patch dilewati."
fi

./bootstrap
./configure --prefix="$SPINE_DIR"
make -j"$(nproc)"
make install
chown root:root "$SPINE_BIN"
chmod u+s "$SPINE_BIN"   # perlu root untuk ping ICMP

mkdir -p "$(dirname "$SPINE_CONF")"
cp spine.conf.dist "$SPINE_CONF"
sed -i -E \
    -e "s|^DB_User\s.*|DB_User         cactiuser|" \
    -e "s|^DB_Pass\s.*|DB_Pass         $PASSWORD|" \
    "$SPINE_CONF"
chown root:www-data "$SPINE_CONF"
chmod 640 "$SPINE_CONF"
cd /

# Isi path Spine agar langsung terisi di wizard
mysql cacti -e "
REPLACE INTO settings (name, value) VALUES
  ('path_spine', '$SPINE_BIN'),
  ('path_spine_config', '$SPINE_CONF');"

# Uji koneksi Spine ke database
SPINE_TEST=$("$SPINE_BIN" -C "$SPINE_CONF" -R -S -V 1 2>&1 || true)
if grep -q 'Connection Failed' <<<"$SPINE_TEST"; then
    echo "⚠️  Spine gagal terhubung ke database, cek $SPINE_CONF"
else
    echo "✅ Spine bisa terhubung ke database."
fi

# ========================
# SELESAI
# ========================
echo ""
echo "🎉 Instalasi Cacti ${CACTI_TAG#release/} dan Spine selesai!"
echo "🌐 Buka wizard: http://$FQDN/install/  (login awal admin / admin)"
echo "🛠  Pilih 'Spine' sebagai Poller Engine. Path Spine: $SPINE_BIN"
