#!/bin/bash

set -e

# Konfigurasi
USERNAME="usernameanda"
PASSWORD="isipassword"
FQDN="namadomain"

echo "========== [ STEP 1 ] Update dan Install Dependencies =========="
sudo apt update && sudo apt upgrade -y

# Install web dan database stack
sudo apt install -y apache2 mariadb-server mariadb-client \
 php php-mysql php-snmp php-gd php-xml php-mbstring php-curl \
 snmp snmpd rrdtool librrds-perl libnet-snmp-perl unzip wget \
 git build-essential libssl-dev libmariadb-dev librrd-dev libsnmp-dev \
 php-ldap php-gmp php-intl php-bcmath php-cli php-common php-pear php-dev

echo "========== [ STEP 2 ] Setup Hostname =========="
sudo hostnamectl set-hostname "$FQDN"

echo "========== [ STEP 3 ] Konfigurasi MariaDB =========="
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$PASSWORD';"
sudo mysql -uroot -p"$PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -uroot -p"$PASSWORD" -e "DROP DATABASE IF EXISTS test;"
sudo mysql -uroot -p"$PASSWORD" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -uroot -p"$PASSWORD" -e "FLUSH PRIVILEGES;"

echo "========== [ STEP 4 ] Import Zona Waktu ke MySQL =========="
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -uroot -p"$PASSWORD" mysql

echo "========== [ STEP 5 ] Membuat Database Cacti =========="
sudo mysql -uroot -p"$PASSWORD" -e "
CREATE DATABASE cacti DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'cactiuser'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON cacti.* TO 'cactiuser'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'cactiuser'@'localhost';
FLUSH PRIVILEGES;"

echo "========== [ STEP 6 ] Unduh dan Setup Cacti =========="
cd /var/www/html
sudo git clone https://github.com/Cacti/cacti.git
cd cacti
sudo git checkout release/1.2
sudo chown -R www-data:www-data /var/www/html/cacti

echo "========== [ STEP 7 ] Import Database Schema =========="
sudo mysql -u root -p"$PASSWORD" cacti < /var/www/html/cacti/cacti.sql

echo "========== [ STEP 8 ] Konfigurasi Cacti =========="
sudo cp include/config.php.dist include/config.php
sudo sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cactiuser';/" include/config.php
sudo sed -i "s/\$database_password = 'cactiuser';/\$database_password = '$PASSWORD';/" include/config.php

echo "========== [ STEP 9 ] Setup Apache VirtualHost =========="
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
sudo systemctl restart apache2

echo "========== [ STEP 10 ] Tambah Cron Job =========="
echo "*/5 * * * * www-data php /var/www/html/cacti/poller.php > /dev/null 2>&1" | sudo tee /etc/cron.d/cacti

echo "========== [ STEP 11 ] Install Spine Poller =========="
cd /tmp
wget https://www.cacti.net/downloads/spine/cacti-spine-latest.tar.gz
tar -zxvf cacti-spine-latest.tar.gz
cd cacti-spine-*
./configure
make
sudo make install

echo "========== [ STEP 12 ] Konfigurasi Spine =========="
sudo cp spine.conf.dist /usr/local/spine/etc/spine.conf
sudo sed -i "s/DB_Password     cactiuser/DB_Password     $PASSWORD/" /usr/local/spine/etc/spine.conf

echo "========== [ DONE ] Instalasi dan Konfigurasi Selesai =========="
echo "🎉 Akses Cacti melalui browser di: http://$FQDN"
echo "🛠 Lanjutkan setup melalui antarmuka web, dan pilih Spine sebagai Poller Engine."
