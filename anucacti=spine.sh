#!/bin/bash

set -e

# Konfigurasi
USERNAME="usernameanda"
PASSWORD="isipassword"
FQDN="namadomain"

echo "[+] Updating and installing dependencies..."
sudo apt update
sudo apt upgrade -y

# Install Apache, MariaDB, PHP and required modules
echo "[+] Installing Apache, MariaDB, PHP and required packages..."
sudo apt install -y apache2 mariadb-server \
 php php-mysql php-snmp php-gd php-xml php-mbstring php-curl \
 snmp snmpd rrdtool librrds-perl libnet-snmp-perl unzip wget \
 git build-essential libssl-dev libmysqlclient-dev librrd-dev libsnmp-dev \
 php-ldap php-gmp php-intl php-bcmath php-cli php-common php-pear php-dev

# Set hostname
echo "[+] Setting hostname to $FQDN..."
sudo hostnamectl set-hostname "$FQDN"

# Configure MariaDB
echo "[+] Securing MariaDB..."
sudo mysql -e "UPDATE mysql.user SET Password = PASSWORD('$PASSWORD') WHERE User = 'root';"
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Create Cacti database and user
echo "[+] Creating Cacti database and user..."
sudo mysql -uroot -p"$PASSWORD" -e "
CREATE DATABASE cacti DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON cacti.* TO 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
FLUSH PRIVILEGES;"

# Import timezone data
echo "[+] Importing timezone data into MySQL..."
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -uroot -p"$PASSWORD" mysql

# Download dan Install Cacti
echo "[+] Downloading and setting up Cacti..."
cd /var/www/html
sudo git clone https://github.com/Cacti/cacti.git
cd cacti
sudo git checkout release/1.2

# Set ownership
sudo chown -R www-data:www-data /var/www/html/cacti

# Import default schema
echo "[+] Importing Cacti default database schema..."
sudo mysql -u root -p"$PASSWORD" cacti < /var/www/html/cacti/cacti.sql

# Configure Cacti settings
echo "[+] Configuring Cacti configuration..."
sudo cp include/config.php.dist include/config.php
sudo sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cactiuser';/" include/config.php
sudo sed -i "s/\$database_password = 'cactiuser';/\$database_password = '$PASSWORD';/" include/config.php

# Configure Apache
echo "[+] Configuring Apache virtual host..."
sudo tee /etc/apache2/sites-available/cacti.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $FQDN
    DocumentRoot /var/www/html/cacti

    <Directory /var/www/html/cacti/>
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

# Configure cron
echo "[+] Setting up cron for poller.php..."
sudo echo "*/5 * * * * www-data php /var/www/html/cacti/poller.php > /dev/null 2>&1" | sudo tee /etc/cron.d/cacti

# Install and configure Spine
echo "[+] Installing Spine poller..."
cd /tmp
wget https://www.cacti.net/downloads/spine/cacti-spine-latest.tar.gz
tar -zxvf cacti-spine-latest.tar.gz
cd cacti-spine-*
./configure
make
sudo make install

# Configure Spine
sudo cp spine.conf.dist /usr/local/spine/etc/spine.conf
sudo sed -i "s/DB_Password     cactiuser/DB_Password     $PASSWORD/" /usr/local/spine/etc/spine.conf

echo "[✓] Installation and configuration complete."
echo ">> Please navigate to http://$FQDN in your browser to finish setup via the web installer."
