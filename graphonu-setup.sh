#!/bin/bash

# ========================
# Cek dan install expect jika belum ada
# ========================
if ! command -v expect &> /dev/null; then
  echo "🔧 'expect' belum terpasang. Menginstal..."
  sudo apt update && sudo apt install -y expect
else
  echo "✅ 'expect' sudah terpasang."
fi

# ========================
# Prompt isian variabel untuk graphnostek.sh
# ========================
read -p "Masukkan IP modem/router: " nostek_target
read -p "Masukkan username login: " nostek_user
read -sp "Masukkan password login: " nostek_pass
echo ""
read -p "Masukkan nama interface (misal ppp0): " nostek_intr

# Simpan isian ke file config jika perlu (opsional) atau langsung digunakan

# ========================
# Deteksi path instalasi Cacti
# ========================
echo "📦 Mencari path instalasi Cacti..."
cacti_dir=$(find /var/www /usr/share /opt -type d -name cacti -print -quit 2>/dev/null)

if [ -z "$cacti_dir" ]; then
  echo "❌ Direktori instalasi Cacti tidak ditemukan secara otomatis."
  echo "Silakan salin skrip graphnostek.sh secara manual ke direktori scripts Cacti Anda."
  exit 1
fi

echo "✅ Cacti ditemukan di: $cacti_dir"

# ========================
# Salin skrip asli graphnostek.sh
# ========================
if [ -d "$cacti_dir/scripts" ]; then
  sudo cp ./graphnostek.sh "$cacti_dir/scripts/graphnostek.sh"
  sudo chmod +x "$cacti_dir/scripts/graphnostek.sh"
  echo "✅ Skrip disalin ke: $cacti_dir/scripts/graphnostek.sh"
else
  echo "⚠️  Direktori scripts tidak ditemukan di dalam $cacti_dir. Silakan cek struktur folder Anda."
fi
