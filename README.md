# Cacti + Spine Installer untuk Ubuntu 24.04

Skrip untuk memasang Cacti dan Spine (poller berbasis C) di Ubuntu Server 24.04 dalam sekali jalan. Database, PHP, Apache, cron, dan Spine langsung diatur sesuai rekomendasi Cacti.

Repo ini juga punya skrip tambahan untuk membuat grafik trafik modem/ONU lewat telnet.

## Isi Repo

| File | Fungsi |
|------|--------|
| `anucacti-spine.sh` | Installer utama Cacti + Spine |
| `nostek-setup.sh` | Setup grafik trafik modem/ONU (daftar perangkat + pasang script poller) |
| `graphnostek.sh` | Script poller yang dipanggil Cacti untuk membaca trafik modem/ONU |
| `MariaDB/99-cacti.cnf` | Contoh tuning MariaDB (installer membuatnya otomatis) |

## Persyaratan

- Ubuntu Server 24.04 LTS, sebaiknya instalasi baru
- Akses root (`sudo`)
- Koneksi internet ke `github.com` dan repo Ubuntu
- Minimal 2 vCPU dan 2 GB RAM (disarankan 4 GB atau lebih)

## Instalasi Cacti + Spine

```bash
wget https://raw.githubusercontent.com/thuekx/Cacti-Spine/main/anucacti-spine.sh
chmod +x anucacti-spine.sh
sudo ./anucacti-spine.sh
```

Skrip akan menanyakan:

1. **Domain (FQDN)**, misalnya `cacti.example.com`.
2. **Password database** untuk user `cactiuser`, minimal 8 karakter. Karakter yang boleh: huruf, angka, dan `. _ @ % + = , ! -`.
3. **Timezone**, default dari sistem (misalnya `Asia/Jakarta`).
4. **Fresh install atau tidak.**
   - `N` (default): lanjut tanpa menghapus apa pun. Skrip berhenti kalau Cacti atau database `cacti` sudah ada.
   - `y`: **menghapus** Apache, PHP, MariaDB, semua database, dan seluruh isi `/var/www/html`, lalu memasang ulang dari nol.

Setelah selesai, buka `http://<domain>/install/`, login dengan `admin` / `admin` (wajib diganti saat login pertama), lalu ikuti wizard dan pilih **Spine** sebagai Poller Engine. Path Spine sudah terisi otomatis.

Untuk memasang versi Cacti tertentu, set `CACTI_VERSION`:

```bash
sudo CACTI_VERSION=1.2.30 ./anucacti-spine.sh
```

### Yang dilakukan installer

1. Memasang paket: Apache, PHP 8.3 beserta ekstensinya, MariaDB, SNMP, RRDtool, dan alat build.
2. Membuat `/etc/mysql/mariadb.conf.d/99-cacti.cnf`: utf8mb4, `innodb_buffer_pool_size` 25% RAM, dan tuning lain yang dicek oleh wizard Cacti.
3. Membuat database `cacti` dan user `cactiuser`, lalu mengimpor data timezone MySQL.
4. Mengatur `php.ini` (Apache dan CLI): `date.timezone`, `memory_limit = 512M`, `max_execution_time = 60`.
5. Mengunduh rilis stabil terbaru Cacti dari GitHub ke `/var/www/html/cacti` dan mengimpor skemanya.
6. Mengatur VirtualHost Apache agar Cacti tampil di root domain (`http://<domain>/`).
7. Memasang cron poller setiap 5 menit.
8. Build Spine dengan versi yang sama dengan Cacti (dengan patch `TINY_BUFSIZE` 64), lalu mengisi `spine.conf` dan menguji koneksi ke database.

### File yang dibuat

| Path | Keterangan |
|------|------------|
| `/var/www/html/cacti` | Aplikasi Cacti |
| `/var/www/html/cacti/include/config.php` | Koneksi database Cacti |
| `/etc/apache2/sites-available/cacti.conf` | VirtualHost Apache |
| `/etc/mysql/mariadb.conf.d/99-cacti.cnf` | Tuning MariaDB |
| `/etc/cron.d/cacti` | Cron poller (5 menit) |
| `/usr/local/spine/bin/spine` | Binary Spine |
| `/usr/local/spine/etc/spine.conf` | Koneksi database Spine |

### Akun

| Item | Nilai |
|------|-------|
| Database | `cacti` |
| User database | `cactiuser` |
| Password database | sesuai input saat instalasi |
| Login web | `admin` / `admin` (diganti saat login pertama) |

## Grafik Trafik Modem/ONU

Untuk modem/ONU yang bisa diakses lewat telnet (misalnya Nostek). Jalankan setelah Cacti terpasang, dari folder repo ini:

```bash
sudo ./nostek-setup.sh
```

Skrip akan:

- memasang `expect` dan `telnet` bila belum ada;
- meminta data perangkat: nama, IP, username, password, mode, dan interface;
- menyimpan daftar perangkat ke `/etc/cacti-nostek/devices.conf` (hanya bisa dibaca root dan `www-data`);
- memasang `graphnostek.sh` ke direktori `scripts` Cacti.

Mode pengambilan data:

| Mode | Perintah di modem | Cara hitung |
|------|-------------------|-------------|
| `ifconfig` | `ifconfig <interface>` | Selisih counter RX/TX dibagi waktu. Sampel pertama bernilai `U` (belum ada pembanding). |
| `wan` | `wan show` | Mengambil angka `bps` yang tampil di baris interface. |

Uji manual:

```bash
sudo -u www-data /var/www/html/cacti/scripts/graphnostek.sh ONU-ZTE1
# contoh output: tx:200000 rx:1000000
```

Output dalam bit/s. Bila gagal (telnet/login gagal, perangkat tidak dikenal), output `tx:U rx:U` dan pesan error ditulis ke stderr. Set `NOSTEK_DEBUG=1` untuk menyimpan output mentah modem di `/var/tmp/cacti-nostek/<nama>.last`.

Lalu buat di Cacti:

1. **Data Input Method** (Console > Data Collection > Data Input Methods)
   - Input Type: `Script/Command`
   - Input String: `<path_cacti>/scripts/graphnostek.sh <name>`
   - Input Field: `name`
   - Output Field: `tx` dan `rx`
2. **Data Source Template** memakai method di atas, tipe `GAUGE`.
3. **Graph Template** untuk `tx` dan `rx` (satuan bit/s).

## Troubleshooting

**Halaman default Apache yang muncul.** Pastikan DNS domain mengarah ke server, lalu:

```bash
sudo a2dissite 000-default
sudo a2ensite cacti
sudo systemctl reload apache2
```

**Diarahkan ke `/cacti/install`.** Cek `/var/www/html/cacti/include/config.php` harus berisi `$url_path = '/';`, dan di database:

```sql
UPDATE cacti.settings SET value = '/' WHERE name = 'url_path';
```

**Tidak bisa login admin/admin.** Hapus cookie browser atau coba jendela incognito.

**Spine gagal konek ke database.** Cek `DB_User` dan `DB_Pass` di `/usr/local/spine/etc/spine.conf`, lalu uji:

```bash
sudo /usr/local/spine/bin/spine -C /usr/local/spine/etc/spine.conf -R -S -V 3
```

**Grafik modem kosong.** Jalankan uji manual di atas dengan `NOSTEK_DEBUG=1`, lalu periksa file `.last` untuk melihat apa yang dikirim modem.

## Kontribusi

Laporan bug dan pull request terbuka untuk siapa saja:

1. Fork repo ini
2. Buat branch: `git checkout -b fitur-anda`
3. Commit perubahan
4. Push dan buat Pull Request

## Penulis dan Lisensi

Dibuat oleh [@thuekx](https://github.com/thuekx). Bebas dipakai untuk keperluan pribadi maupun komersial. Kredit untuk komunitas [KoLU](https://kolu.web.id).
