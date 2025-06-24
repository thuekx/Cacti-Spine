# 📦 Cacti + Spine Auto Installer untuk Ubuntu 24.04

Skrip interaktif untuk melakukan instalasi lengkap Cacti dan Spine polling engine, termasuk semua konfigurasi penting, optimasi MariaDB, dan pengaturan Apache yang sesuai standar dokumentasi Cacti.

---

## ✨ Fitur

- Instalasi Cacti terbaru dari GitHub
- Build dan install Spine poller dari source
- Konfigurasi database & timezone otomatis
- Patch `TINY_BUFSIZE` otomatis untuk Spine
- UTF8MB4 full compliance untuk MariaDB
- Wizard langsung tersedia di `http://namadomain/install`
- Auto tuning: buffer pool, temp table, collation
- Interaktif: Username, password DB, dan FQDN dapat diisi saat dijalankan

---

## 🖥️ Persyaratan Sistem

- Ubuntu Server 24.04 LTS (fresh recommended)
- Akses root / sudo
- Koneksi internet
- Minimal 2 vCPU, 2 GB RAM (direkomendasikan ≥ 4 GB RAM)

---

## 🚀 Cara Instalasi

### 1. Unduh skrip:
```bash
wget https://raw.githubusercontent.com/thuekx/Cacti-Spine/main/anucacti-spine.sh
chmod +x anucacti-spine.sh
```

### 2. Jalankan skrip:
```bash
./anucacti-spine.sh
```

### 3. Isi prompt:
- Nama user sistem (untuk cron, misal: `www-data`)
- Password user database `cactiuser`
- Domain FQDN (contoh: `cacti.example.com`)

> ⚠️ Skrip akan menanyakan apakah ingin menghapus instalasi Apache, PHP, dan MariaDB yang ada — pilih "y" untuk fresh install.

---

## 🔐 Informasi Akun & Database

| Komponen       | Keterangan                  |
|----------------|-----------------------------|
| DB Name        | `cacti`                     |
| DB User        | `cactiuser`                 |
| DB Password    | Diisi saat instalasi        |
| Default Login  | **Username**: `admin`<br>**Password**: `admin` (akan diminta diubah saat login pertama) |

---

## 🌐 Akses Web

Setelah instalasi selesai:

- Buka: `http://yourdomain/install/`
- Ikuti wizard setup
- Pilih `Spine` sebagai Poller Engine saat instalasi

---

## 🛠️ Troubleshooting

### 🔹 Tidak bisa login dengan admin/admin?
- Pastikan instalasi berhasil hingga selesai
- Jika login gagal: hapus cookie browser, coba tab incognito

### 🔹 Halaman default Apache muncul?
- Pastikan domain FQDN sudah benar
- Jalankan ulang:
  ```bash
  sudo a2ensite cacti
  sudo systemctl reload apache2
  ```

### 🔹 Tetap diarahkan ke `/cacti/install`?
- Pastikan file ini ada dan berisi:
  ```php
  $url_path = '/';
  ```
  di dalam `/var/www/html/cacti/include/config.php`

- Pastikan ini di database:
  ```sql
  UPDATE cacti.settings SET value = '/' WHERE name = 'url_path';
  ```

---

## 📄 Struktur File yang Dibuat

| Path File                          | Deskripsi                             |
|-----------------------------------|----------------------------------------|
| `/var/www/html/cacti`             | Direktori utama Cacti                  |
| `/etc/apache2/sites-available/cacti.conf` | VirtualHost Apache Cacti        |
| `/etc/mysql/mariadb.conf.d/50-cacti.cnf` | Optimasi MariaDB untuk Cacti     |
| `/etc/cron.d/cacti`               | Cron untuk polling tiap 5 menit        |
| `/usr/local/spine/etc/spine.conf` | Konfigurasi Spine Poller               |

---

## 📦 Build Spine Manual (Jika diperlukan)

```bash
cd /tmp/spine
./bootstrap
./configure
make
sudo make install
```

---

## 🔧 Tuning MariaDB

Konfigurasi yang disisipkan otomatis:

```ini
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_heap_table_size = 256M
tmp_table_size = 256M
innodb_buffer_pool_size = 4096M
innodb_doublewrite = OFF
```

---

## 👤 Penulis

- 👨‍💻 GitHub: [@thuekx](https://github.com/thuekx)
- 📂 Proyek: [Cacti-Spine](https://github.com/thuekx/Cacti-Spine)

---

## 🤝 Kontribusi

Kontribusi terbuka untuk siapa saja!  
Jika Anda menemukan bug, ingin menambahkan fitur, atau menyempurnakan dokumentasi:

1. Fork repository ini
2. Buat branch baru (`git checkout -b fitur-anda`)
3. Commit perubahan (`git commit -am 'Tambahkan fitur A'`)
4. Push ke branch (`git push origin fitur-anda`)
5. Buat Pull Request

---

## 📄 Lisensi

Proyek ini dirilis di bawah lisensi open-source dan bebas digunakan untuk keperluan pribadi atau komersial. Kredit pada komunitas [KoLU](https://kolu.web.id)
