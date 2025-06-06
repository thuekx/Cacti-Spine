#!/bin/bash
set -e

# ========================
# INPUT USER INTERAKTIF
# ========================
echo "📋 Masukkan konfigurasi instalasi Cacti"

read -p "🧑  Masukkan nama user sistem (untuk cron): " USERNAME
read -s -p "🔐 Masukkan password database cactiuser: " PASSWORD
echo ""
read -p "🌐 Masukkan domain (FQDN), contoh: cacti.example.com: " FQDN

INSTALL_DIR="/var/www/html/cacti"
SPINE_CONF="/usr/local/spine/etc/spine.conf"

# ========================
# CLEANUP: Optional Full Reset
# ========================
echo "⚠️  Skrip ini akan menghapus Apache, PHP, dan MariaDB dari sistem!"
read -p "Lanjutkan pembersihan dan install ulang dari awal? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🧹 Membersihkan sistem..."

    sudo systemctl stop apache2 mariadb || true

    sudo apt purge -y apache2* php* mysql* mariadb* libapache2-mod-php* \
      php-pear php-dev php-cli php-common php-mysql \
      php-mbstring php-xml php-gd php-snmp php-curl \
      php-ldap php-gmp php-intl php-bcmath

    sudo apt autoremove -y
    sudo apt autoclean

    sudo rm -rf /etc/apache2 /etc/mysql /etc/php /var/lib/mysql /var/www/html/*
    sudo rm -rf /var/log/apache2 /var/log/mysql /etc/systemd/system/mariadb.service.d

    echo "✅ Pembersihan selesai."
else
    echo "❌ Proses dibatalkan oleh pengguna."
    exit 1
fi

# ========================
# STEP 1: Install Dependencies
# ========================
echo "🔧 Menginstal dependencies..."
REQUIRED_PACKAGES="apache2 mariadb-server php php-mysql php-snmp php-gd php-xml php-mbstring php-curl snmp snmpd rrdtool git build-essential libssl-dev libmariadb-dev librrd-dev libsnmp-dev php-ldap php-gmp php-intl php-bcmath php-cli php-common php-pear php-dev wget unzip autoconf automake libtool xsltproc docbook-xsl docbook-utils pkg-config help2man"
sudo apt update
sudo apt install -y $REQUIRED_PACKAGES

# ========================
# STEP 2: Set Hostname
# ========================
sudo hostnamectl set-hostname "$FQDN"

# ========================
# STEP 3: Konfigurasi MariaDB
# ========================
echo "🗃️  Setup database MariaDB..."
sudo mysql -e "
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;"

sudo mysql -e "
CREATE DATABASE IF NOT EXISTS cacti DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON cacti.* TO 'cactiuser'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'cactiuser'@'localhost';
FLUSH PRIVILEGES;"

mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql mysql

# ========================
# STEP 4: Download Cacti
# ========================
echo "⬇️ Mengunduh Cacti release terbaru..."
cd /tmp
LATEST_URL=$(curl -s https://api.github.com/repos/Cacti/cacti/releases/latest | grep "tarball_url" | cut -d '"' -f 4)
wget -O cacti-latest.tar.gz "$LATEST_URL"
tar -xzf cacti-latest.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "Cacti-cacti-*")
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"
sudo chown -R www-data:www-data "$INSTALL_DIR"

# ========================
# STEP 5: Import Schema
# ========================
sudo mysql cacti < "$INSTALL_DIR/cacti.sql"

# ========================
# STEP 6: Konfigurasi config.php
# ========================
cp "$INSTALL_DIR/include/config.php.dist" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cactiuser';/" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_password = 'cactiuser';/\$database_password = '$PASSWORD';/" "$INSTALL_DIR/include/config.php"
echo "\$url_path = '/';" | sudo tee -a "$INSTALL_DIR/include/config.php" > /dev/null

# ========================
# STEP 7: Apache Setup (Alias root → cacti)
# ========================
sudo tee /etc/apache2/sites-available/cacti.conf > /dev/null <<EOF
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

# Nonaktifkan site default Apache & aktifkan Cacti
sudo a2dissite 000-default.conf || true
sudo rm -f /var/www/html/index.html
sudo a2ensite cacti
sudo a2enmod rewrite
sudo systemctl reload apache2

# ========================
# STEP 8: Setup Cron Job
# ========================
echo "*/5 * * * * www-data php $INSTALL_DIR/poller.php > /dev/null 2>&1" | sudo tee /etc/cron.d/cacti

# ========================
# STEP 9: Install Spine dari GitHub (dengan patch)
# ========================
echo "🐛 Mengunduh Spine dari GitHub dan patch TINY_BUFSIZE..."

cd /tmp
if [ -d "spine" ]; then
  echo "📂 Direktori spine sudah ada, menghapus lama..."
  rm -rf spine
fi

git clone https://github.com/Cacti/spine.git
cd spine

# ✅ Cari dan patch file php.c
echo "🔍 Mencari lokasi file php.c untuk patching..."
PHP_C_FILE=$(find . -type f -name 'php.c' | head -n 1)

if [ -z "$PHP_C_FILE" ]; then
  echo "❌ File php.c tidak ditemukan. Patch gagal."
  exit 1
else
  echo "✅ Menemukan $PHP_C_FILE. Melakukan patch..."
  sed -i 's/#define TINY_BUFSIZE.*/#define TINY_BUFSIZE 64/' "$PHP_C_FILE"
fi

./bootstrap
./configure

if command -v help2man >/dev/null 2>&1; then
  make
  sudo make install
else
  echo "⚠️  help2man tidak ditemukan, melanjutkan build tanpa manpage..."
  make -k
  sudo make -k install
fi

# ========================
# STEP 10: Konfigurasi Spine
# ========================
sudo mkdir -p "$(dirname "$SPINE_CONF")"
sudo cp spine.conf.dist "$SPINE_CONF"
sudo sed -i "s/^DB_Password.*/DB_Password     $PASSWORD/" "$SPINE_CONF"

# ========================
# DONE
# ========================
echo ""
echo "🎉 Instalasi Cacti dan Spine selesai!"
echo "🌐 Akses wizard melalui: http://$FQDN/install/"
echo "🛠 Pilih 'Spine' sebagai Poller Engine saat wizard."

# ========================
# Konfigurasi MariaDB untuk Cacti (UTF8MB4 full compliance)
# ========================
echo "🛠 Menambahkan konfigurasi MariaDB khusus untuk Cacti (UTF8MB4)..."
sudo tee /etc/mysql/mariadb.conf.d/50-cacti.cnf > /dev/null <<EOF
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_heap_table_size = 256M
tmp_table_size = 256M
innodb_buffer_pool_size = 4096M
innodb_doublewrite = OFF

EOF

# Restart untuk menerapkan perubahan
sudo systemctl restart mariadb
