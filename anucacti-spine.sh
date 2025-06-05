#!/bin/bash

set -e

# Konfigurasi
USERNAME="usernameanda"
PASSWORD="isipassword"
FQDN="namadomain"
INSTALL_DIR="/var/www/html/cacti"
SPINE_CONF="/usr/local/spine/etc/spine.conf"

# --- UTILITY FUNCTIONS ---
check_dependency() {
  echo -n "Checking for $1 ... "
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ MISSING"
    MISSING_PACKAGES+=("$2")
  else
    echo "✅ FOUND"
  fi
}

# --- STEP 1: CHECK & INSTALL DEPENDENCIES ---
echo "========== [ STEP 1 ] Dependency Validation =========="
MISSING_PACKAGES=()
check_dependency apache2 apache2
check_dependency mariadb mysql-server
check_dependency php php
check_dependency snmp snmp
check_dependency rrdtool rrdtool
check_dependency gcc build-essential
check_dependency make build-essential
check_dependency wget wget
check_dependency git git

# Tambahan PHP modules (minimal)
PHP_MODULES=(
  php-mysql php-snmp php-gd php-xml php-mbstring php-curl php-ldap
  php-gmp php-intl php-bcmath php-cli php-common php-pear php-dev
)
for module in "${PHP_MODULES[@]}"; do
  dpkg -s $module >/dev/null 2>&1 || MISSING_PACKAGES+=($module)
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
  echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
  sudo apt update
  sudo apt install -y "${MISSING_PACKAGES[@]}"
else
  echo "✅ Semua dependency telah terpasang."
fi

# --- STEP 2: Hostname Setup ---
echo "========== [ STEP 2 ] Hostname Setup =========="
sudo hostnamectl set-hostname "$FQDN"

# --- STEP 3: MariaDB Configuration ---
echo "========== [ STEP 3 ] Database Configuration =========="
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$PASSWORD';"
sudo mysql -uroot -p"$PASSWORD" -e "
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;"
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -uroot -p"$PASSWORD" mysql

sudo mysql -uroot -p"$PASSWORD" -e "
CREATE DATABASE IF NOT EXISTS cacti DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON cacti.* TO 'cactiuser'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'cactiuser'@'localhost';
FLUSH PRIVILEGES;"

# --- STEP 4: Download Latest Cacti Release from GitHub ---
echo "========== [ STEP 4 ] Downloading Latest Cacti Release =========="
LATEST_URL=$(curl -s https://api.github.com/repos/Cacti/cacti/releases/latest | grep "tarball_url" | cut -d '"' -f 4)
echo "Found latest release: $LATEST_URL"

cd /tmp
wget -O cacti.tar.gz "$LATEST_URL"
tar -xzf cacti.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "Cacti-cacti-*")
sudo mv "$EXTRACTED_DIR" "$INSTALL_DIR"
sudo chown -R www-data:www-data "$INSTALL_DIR"

# --- STEP 5: Import Cacti SQL Schema ---
echo "========== [ STEP 5 ] Importing Cacti Schema =========="
sudo mysql -uroot -p"$PASSWORD" cacti < "$INSTALL_DIR/cacti.sql"

# --- STEP 6: Config PHP Cacti ---
echo "========== [ STEP 6 ] Configuring Cacti PHP =========="
cp "$INSTALL_DIR/include/config.php.dist" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cactiuser';/" "$INSTALL_DIR/include/config.php"
sed -i "s/\$database_password = 'cactiuser';/\$database_password = '$PASSWORD';/" "$INSTALL_DIR/include/config.php"

# --- STEP 7: Apache Setup ---
echo "========== [ STEP 7 ] Apache Configuration =========="
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

# --- STEP 8: Cron Job Setup ---
echo "========== [ STEP 8 ] Setup Cron Job =========="
echo "*/5 * * * * www-data php $INSTALL_DIR/poller.php > /dev/null 2>&1" | sudo tee /etc/cron.d/cacti

# --- STEP 9: Install Spine Poller ---
echo "========== [ STEP 9 ] Install Spine Poller =========="
cd /tmp
wget https://www.cacti.net/downloads/spine/cacti-spine-latest.tar.gz
tar -xzf cacti-spine-latest.tar.gz
cd cacti-spine-*
./configure
make
sudo make install

# --- STEP 10: Configure Spine ---
echo "========== [ STEP 10 ] Configure Spine =========="
sudo cp spine.conf.dist "$SPINE_CONF"
sudo sed -i "s/^DB_Password.*/DB_Password     $PASSWORD/" "$SPINE_CONF"

# --- DONE ---
echo "🎉 INSTALASI SELESAI!"
echo "🌐 Akses Cacti melalui: http://$FQDN"
echo "🛠 Lanjutkan konfigurasi melalui web GUI dan pilih Spine sebagai poller engine."
