# 📡 Cacti & Spine Installer for Ubuntu 24.04

Skrip `anucacti-spine.sh` ini secara otomatis menginstal dan mengonfigurasi **Cacti Monitoring System** beserta **Spine Poller** di server berbasis **Ubuntu 24.04 LTS**, menggunakan konfigurasi default dan siap pakai melalui antarmuka web.

---

## ✅ Fitur

- Purge instalasi sebelumnya jika ada (Apache, MariadB, PHP)
- Instalasi otomatis: Apache, MariaDB, PHP, SNMP, RRDTool
- Setup database dan pengguna `cactiuser`
- Konfigurasi domain otomatis (`Namadomainanda`)
- Install dan konfigurasi Spine sebagai poller engine
- Setup VirtualHost Apache
- Menambahkan cron job untuk polling Cacti
- Siap diakses melalui browser (web installer)

---

## 🔧 Persyaratan Sistem

- Ubuntu Server 24.04 LTS
- Akses root atau user dengan sudo
- Terhubung ke internet untuk mengunduh dependensi

---

## 🚀 Cara Instalasi

1. Clone repositori ini:
    ```bash
    git clone https://github.com/thuekx/Cacti-Spine.git
    cd cacti-installer
    ```

2. Jadikan skrip dapat dieksekusi:
    ```bash
    chmod +x anucacti-spine.sh
    ```

3. Jalankan skrip:
    ```bash
    sudo ./anucacti-spine.sh
    ```

---

## 🔐 Informasi Akun & Database Default

| Komponen       | Username   | Password     |
|----------------|------------|--------------|
| MySQL root     | root       | `isipassword`|
| Cacti DB user  | cactiuser  | `isipassword`|
| Linux user     | ithero     | `isipassword`|

> ⚠️ **Catatan:** Demi keamanan, ubahlah password default ini setelah instalasi.

---

## 🌐 Akses Web

Setelah skrip selesai dijalankan, buka browser dan akses:

Ikuti langkah wizard instalasi web:
1. Cek requirement
2. Pilih Spine sebagai poller engine
3. Selesaikan instalasi dan login ke dashboard Cacti

---

## 🛠 Troubleshooting

- **Error akses domain**: Pastikan DNS `namadomainanda.com` sudah diarahkan ke IP server Anda.
- **Permission issues**: Pastikan direktori `/var/www/html/cacti` dimiliki oleh `www-data`.
- **Polling tidak berjalan**: Periksa cron job `poller.php` di `/etc/cron.d/cacti`.

---

## 🧾 Lisensi

Skrip ini bersifat open-source dan bebas digunakan untuk keperluan pribadi atau komersial. Kredit pada komunitas `kolu.web.id`.

---

## 🤝 Kontribusi

Pull request sangat disambut untuk:
- Penambahan support distro lain
- Hardening keamanan default
- Dockerfile/Ansible Playbook

---

## 📬 Kontak

Untuk pertanyaan lebih lanjut, silakan hubungi:

**Nama**: thuekx  
**Email**: thuekx@kolu.web.id  
**Domain**: [kolu.web.id](http://kolu.web.id)

