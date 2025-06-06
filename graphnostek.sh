#!/bin/bash

# ========================
# Prompt isian variabel
# ========================
read -p "Masukkan IP modem/router: " nostek_target
read -p "Masukkan username login: " nostek_user
read -sp "Masukkan password login: " nostek_pass
echo ""
read -p "Masukkan nama interface (misal ppp0): " nostek_intr

# ========================
# File log dan temp
# ========================
nostek_filetmp=/tmp/nostekspeed.tmp
nostek_filelog=/tmp/nostekspeed.log

# ========================
# Cek dan install expect jika belum ada
# ========================
if ! command -v expect &> /dev/null; then
  echo "🔧 'expect' belum terpasang. Menginstal..."
  sudo apt update && sudo apt install -y expect
fi

# ========================
# Ambil data via Telnet
# ========================
{
  echo -n "$(date)"
  expect -c "
    set timeout 10
    spawn telnet $nostek_target
    expect \"*ogin:\"
    send \"$nostek_user\r\"
    expect \"*assword:\"
    send \"$nostek_pass\r\"
    expect \"*#\"
    send \"ifconfig $nostek_intr | grep bytes\r\"
    expect \"*#\"
    send \"exit\r\"
    exit
  "
} | grep RX | sed -e 's/^       //g' -e 's/:/=/g' >> $nostek_filetmp

# ========================
# Simpan histori 2 baris
# ========================
if grep -q RX $nostek_filetmp; then
  head -1 $nostek_filelog >> $nostek_filetmp
  cat $nostek_filetmp > $nostek_filelog
fi

# ========================
# Hitung Bandwidth TX/RX
# ========================
if [ "$(wc -l < $nostek_filelog)" = "2" ]; then
  R2=$(head -1 $nostek_filelog | cut -d'=' -f2 | awk '{print $1}')
  T2=$(head -1 $nostek_filelog | cut -d'=' -f3 | awk '{print $1}')
  R1=$(tail -1 $nostek_filelog | cut -d'=' -f2 | awk '{print $1}')
  T1=$(tail -1 $nostek_filelog | cut -d'=' -f3 | awk '{print $1}')

  nostek_tbps=$(( (T2 - T1) / 300 ))
  nostek_rbps=$(( (R2 - R1) / 300 ))

  [ "$nostek_tbps" -ge 1250000 ] && nostek_tbps=0
  [ "$nostek_rbps" -ge 1250000 ] && nostek_rbps=0

  echo "tx:$nostek_tbps rx:$nostek_rbps"
else
  echo "tx:0 rx:0"
fi
