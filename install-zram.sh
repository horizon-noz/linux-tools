#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# ZRAM PERFORMANCE - ARCHCRAFT / ARCH LINUX
# Target: 8 GB RAM, AMD Ryzen 5 4600G
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "Jalankan: sudo bash $0"
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: Script ini hanya untuk Arch Linux."
    exit 1
fi

BACKUP="/var/backups/zram-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

echo "======================================"
echo "   ARCHCRAFT ZRAM PERFORMANCE SETUP"
echo "======================================"

# Backup konfigurasi sebelumnya
for file in \
    /etc/systemd/zram-generator.conf \
    /etc/sysctl.d/99-zram-performance.conf
do
    if [[ -f "$file" ]]; then
        cp -a --parents "$file" "$BACKUP/"
    fi
done

echo "[1/5] Menginstal zram-generator..."
pacman -S --needed --noconfirm zram-generator

echo "[2/5] Memeriksa service ZRAM alternatif..."

for service in zramswap.service zramd.service; do
    if systemctl cat "$service" >/dev/null 2>&1; then
        systemctl disable --now "$service" || {
            echo "PERINGATAN: Periksa service $service secara manual."
        }
    fi
done

echo "[3/5] Membuat konfigurasi ZRAM..."

mkdir -p /etc/systemd

cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

echo "[4/5] Mengoptimalkan virtual memory..."

cat > /etc/sysctl.d/99-zram-performance.conf <<'EOF'
vm.swappiness = 100
vm.page-cluster = 0
EOF

sysctl --system

echo "[5/5] Memuat ulang systemd..."
systemctl daemon-reload

echo
echo "======================================"
echo " KONFIGURASI SELESAI!"
echo "======================================"
echo "Ukuran ZRAM : Maksimal 4 GiB"
echo "Algoritma   : zstd"
echo "Prioritas   : 100"
echo "Swappiness  : 100"
echo "Backup      : $BACKUP"
echo
echo "Restart komputer:"
echo "sudo reboot"
echo
echo "Setelah reboot, cek dengan:"
echo "zramctl"
echo "swapon --show"
echo "free -h"
