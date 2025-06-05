#!/bin/bash

set -e

# ========================
# KONFIGURASI
# ========================
USERNAME="usernameanda"
PASSWORD="isipassword"
FQDN="namadomain"
INSTALL_DIR="/var/www/html/cacti"
SPINE_CONF="/usr/local/spine/etc/spine.conf"

# ========================
# STEP 1: Update & Install Dependencies
# ========================
echo "=== [1/10] Memeriksa dan memasang dependencies..."
REQUIRED_PACKAGES="apache2 mariadb-server php php-mysql php-snmp php-gd php-xml php-mbstring php-curl snmp snmpd rrdtool git build-essential libssl-dev libmariadb-dev librrd-dev libsnmp-dev php-ldap php-gmp php-intl php-bcmath php-cli php-common php-pear php-dev wget unzip"
sudo apt update
sudo apt install -y $REQUIRED_PACKAGES

# ========================
# STEP 2: Set Hostname
# ========================
echo "=== [2/10] Mengatur hostname: $FQDN"
sudo hostnamectl set-hostname "$FQDN"

# ========================
# STEP 3: Konfigurasi MariaDB (tanpa password root)
# ========================
echo "=== [3/10] Mengonfigurasi database..."
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

echo "=== [3.1] Mengimpor data zona waktu ke MySQL..."
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql mysql

# ========================
# STEP 4: Download Cacti dari GitHub (latest release)
# ========================
echo "=== [4/10] Mengunduh Cacti versi terbaru dari GitHub..."
cd /tmp
LATEST_URL=$(curl -s https://api.github.com/repos/Cacti/cacti/releases/latest | grep "tarball_url" | cut -d '"' -f 4)
wget -O cacti-latest.tar.gz "$LATEST_URL"
tar -xzf cacti-latest.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "Cacti-cacti-*")
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"
sudo chown -R www-data:www-data "$INSTALL_DIR"

# ========================
# STEP 5: Import Database Schema Cacti
# ========================
echo "=== [5/10] Mengimpor schema awal Cacti ke database..."
sudo mysql cacti < "$INSTALL_DIR/cacti.sql"

# ========================
# STEP 6: Konfigurasi PHP Cacti
# ========================
echo "=== [6/10] Mengonfigurasi file config.php..."
cp "$INSTALL_DIR/include/config.php.dist" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cactiuser';/" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_password = 'cactiuser';/\$database_password = '$PASSWORD';/" "$INSTALL_DIR/include/config.php"

# ========================
# STEP 7: Konfigurasi Apache
# ========================
echo "=== [7/10] Menambahkan konfigurasi Apache VirtualHost..."
sudo tee /etc/apache2/sites-available/cacti.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $FQDN
    DocumentRoot $INSTALL_DIR

    <Directory $INSTALL_DIR/>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/cacti_error.log
    CustomLog \${APACHE_LOG_DIR}/cacti_access.log combined
</VirtualHost>
EOF

sudo a2ensite cacti
sudo a2enmod rewrite
sudo systemctl reload apache2

# ========================
# STEP 8: Tambahkan Cron Job Poller
# ========================
echo "=== [8/10] Menambahkan cron job untuk polling..."
echo "*/5 * * * * www-data php $INSTALL_DIR/poller.php > /dev/null 2>&1" | sudo tee /etc/cron.d/cacti

# ========================
# STEP 9: Install Spine Poller
# ========================
echo "=== [9/10] Menginstal Spine dari source..."
cd /tmp
wget https://www.cacti.net/downloads/spine/cacti-spine-latest.tar.gz
tar -xzf cacti-spine-latest.tar.gz
cd cacti-spine-*
./configure
make
sudo make install

# ========================
# STEP 10: Konfigurasi Spine
# ========================
echo "=== [10/10] Mengonfigurasi Spine..."
sudo mkdir -p "$(dirname "$SPINE_CONF")"
sudo cp spine.conf.dist "$SPINE_CONF"
sudo sed -i "s/^DB_Password.*/DB_Password     $PASSWORD/" "$SPINE_CONF"

# ========================
# DONE
# ========================
echo ""
echo "🎉 Instalasi Cacti dan Spine selesai!"
echo "🌐 Silakan akses di: http://$FQDN"
echo "🛠 Lanjutkan konfigurasi lewat browser, dan pilih 'Spine' sebagai Poller Engine."
