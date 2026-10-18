#!/usr/bin/env bash
# install-zram.sh — cross-distro zram + optional swapfile setup.
# Detects RAM, filesystem, free space, existing swap/zram, and boot configuration.
# Run as a normal user; sudo is used for system changes.
set -Eeuo pipefail

VERSION="1.0.0"
SWAPFILE="${SWAPFILE:-/swapfile}"
SWAPFILE_SIZE="${SWAPFILE_SIZE:-auto}"       # auto, or e.g. 4G / 8192M
ZRAM_PERCENT="${ZRAM_PERCENT:-50}"            # percentage of detected RAM
ZRAM_ALGORITHM="${ZRAM_ALGORITHM:-zstd}"     # falls back if kernel doesn't support it
ZRAM_PRIORITY="${ZRAM_PRIORITY:-100}"
SWAPFILE_PRIORITY="${SWAPFILE_PRIORITY:-10}"
CONFIG_DIR="/etc"
ZRAM_CONFIG="/etc/default/zramswap"
SYSCTL_CONFIG="/etc/sysctl.d/99-zram-swap.conf"
FSTAB="/etc/fstab"

say()  { printf '\033[1;32m[zram]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[zram warning]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[zram error]\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
bytes_human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }

[[ "$(id -u)" -ne 0 ]] || die "Jalankan sebagai user biasa, jangan langsung dengan sudo."
has sudo || die "Perintah sudo tidak ditemukan."
has awk && has grep && has sed && has df && has findmnt || die "Tool dasar (awk, grep, sed, df, findmnt) wajib tersedia."
sudo -v

# RAM detection in bytes (prefer MemTotal from procfs).
RAM_KB="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
[[ "$RAM_KB" =~ ^[0-9]+$ ]] || die "Gagal mendeteksi RAM dari /proc/meminfo."
RAM_BYTES=$((RAM_KB * 1024))
RAM_GIB=$(( (RAM_BYTES + 1073741823) / 1073741824 ))
say "RAM terdeteksi: ${RAM_GIB} GiB ($(bytes_human "$RAM_BYTES"))"

# zram size: 50% RAM, clamp 1–8 GiB by default. Can override ZRAM_PERCENT.
ZRAM_BYTES=$(( RAM_BYTES * ZRAM_PERCENT / 100 ))
(( ZRAM_BYTES < 1073741824 )) && ZRAM_BYTES=1073741824
(( ZRAM_BYTES > 8589934592 )) && ZRAM_BYTES=8589934592
say "Target zram: $(bytes_human "$ZRAM_BYTES") (${ZRAM_PERCENT}% RAM, dibatasi 1–8 GiB)"

# Detect root filesystem and storage characteristics before planning a swapfile.
ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_FSTYPE="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
ROOT_TARGET="$(findmnt -n -o TARGET / 2>/dev/null || printf '/')"
ROOT_AVAIL_KB="$(df -Pk / | awk 'NR==2 {print $4}')"
ROOT_AVAIL_BYTES=$(( ${ROOT_AVAIL_KB:-0} * 1024 ))
ROOT_TOTAL_KB="$(df -Pk / | awk 'NR==2 {print $2}')"
ROOT_TOTAL_BYTES=$(( ${ROOT_TOTAL_KB:-0} * 1024 ))
say "Root storage: source=${ROOT_SOURCE:-unknown}, filesystem=${ROOT_FSTYPE:-unknown}, mount=${ROOT_TARGET}"
say "Ruang kosong root: $(bytes_human "$ROOT_AVAIL_BYTES") dari $(bytes_human "$ROOT_TOTAL_BYTES")"

# Detect active swap devices/files and zram devices.
say "Swap yang sedang aktif:"
if has swapon; then swapon --show --bytes --output NAME,TYPE,SIZE,USED,PRIO || true; fi
ZRAM_EXISTING="$(swapon --show=NAME --noheadings 2>/dev/null | grep -E '/dev/zram[0-9]+' || true)"
SWAPFILE_ACTIVE="$(swapon --show=NAME --noheadings 2>/dev/null | grep -Fx "$SWAPFILE" || true)"

# Select swapfile size: default roughly RAM, clamped 2–8 GiB, but only if space allows.
if [[ "$SWAPFILE_SIZE" == "auto" ]]; then
  SWAP_BYTES="$RAM_BYTES"
  (( SWAP_BYTES < 2147483648 )) && SWAP_BYTES=2147483648
  (( SWAP_BYTES > 8589934592 )) && SWAP_BYTES=8589934592
else
  # Parse sizes like 4G, 4096M, or bytes.
  if [[ "$SWAPFILE_SIZE" =~ ^([0-9]+)([GgMmKk]?)$ ]]; then
    n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
    case "$unit" in
      G|g) SWAP_BYTES=$((n * 1073741824)) ;;
      M|m) SWAP_BYTES=$((n * 1048576)) ;;
      K|k) SWAP_BYTES=$((n * 1024)) ;;
      *) SWAP_BYTES="$n" ;;
    esac
  else
    die "SWAPFILE_SIZE tidak valid. Gunakan auto, 4G, 4096M, atau angka byte."
  fi
fi

# Reserve at least 1 GiB (or 10% of root volume, whichever is larger).
RESERVE_BYTES=$(( ROOT_TOTAL_BYTES / 10 ))
(( RESERVE_BYTES < 1073741824 )) && RESERVE_BYTES=1073741824
SAFE_AVAILABLE=$(( ROOT_AVAIL_BYTES - RESERVE_BYTES ))
(( SAFE_AVAILABLE < 0 )) && SAFE_AVAILABLE=0

# Swapfiles on Btrfs need special handling; safest portable default is skip swapfile.
SWAPFILE_OK=1
case "$ROOT_FSTYPE" in
  btrfs)
    SWAPFILE_OK=0
    warn "Root filesystem Btrfs terdeteksi. Swapfile otomatis dilewati untuk menghindari file tanpa NOCOW/kompatibilitas yang salah."
    warn "zram tetap bisa diaktifkan. Buat swapfile Btrfs terpisah dengan prosedur khusus bila memang diperlukan."
    ;;
  zfs|overlay|squashfs|nfs|cifs|fuse.*)
    SWAPFILE_OK=0
    warn "Filesystem root '$ROOT_FSTYPE' tidak didukung aman oleh pembuatan swapfile generik; swapfile dilewati."
    ;;
esac

if (( SWAP_BYTES > SAFE_AVAILABLE )); then
  warn "Target swapfile $(bytes_human "$SWAP_BYTES") melebihi ruang aman yang tersedia $(bytes_human "$SAFE_AVAILABLE")."
  if (( SAFE_AVAILABLE >= 1073741824 )); then
    SWAP_BYTES=$(( SAFE_AVAILABLE / 1073741824 * 1073741824 ))
    say "Ukuran swapfile diturunkan menjadi $(bytes_human "$SWAP_BYTES")."
  else
    SWAPFILE_OK=0
    warn "Ruang kosong terlalu sedikit setelah cadangan 1 GiB/10%; swapfile dilewati."
  fi
fi

# Probe available package manager.
PM=""
for p in apt-get dnf pacman zypper apk xbps-install emerge yum; do
  if has "$p"; then PM="$p"; break; fi
done
[[ -n "$PM" ]] || die "Package manager tidak dikenali. Install util-linux, systemd (systemctl), and zram-generator/service manually."

# Install optional zram support package where distro provides one.
case "$PM" in
  apt-get)
    # Debian-family's zramswap package/service is common; don't assume it exists on all releases.
    if ! has zramctl && ! has systemctl; then sudo apt-get update; sudo apt-get install -y util-linux systemd; fi
    if ! dpkg-query -W -f='${Status}' zram-tools 2>/dev/null | grep -q 'install ok installed'; then
      sudo apt-get update
      sudo apt-get install -y zram-tools || warn "Paket zram-tools tidak tersedia; mencoba systemd zram-generator bila tersedia."
    fi
    ;;
  dnf)
    sudo dnf install -y systemd zram-generator-defaults || sudo dnf install -y zram-generator || warn "zram-generator tidak tersedia di repository."
    ;;
  pacman)
    sudo pacman -Sy --needed --noconfirm systemd
    ;;
  zypper)
    sudo zypper --non-interactive install systemd || true
    ;;
  apk)
    sudo apk add util-linux systemd || warn "Alpine biasanya memakai OpenRC; aktivasi systemd tidak otomatis didukung."
    ;;
  xbps-install)
    sudo xbps-install -Sy util-linux systemd
    ;;
  emerge)
    sudo emerge --ask=n sys-apps/util-linux sys-apps/systemd || warn "Pastikan systemd digunakan sebagai init."
    ;;
  yum)
    sudo yum install -y systemd util-linux || true
    ;;
esac

# Ask before changing active swap or service config.
printf '\nRencana:\n'
printf '  • zram: %s, algoritma %s (jika didukung), prioritas %s\n' "$(bytes_human "$ZRAM_BYTES")" "$ZRAM_ALGORITHM" "$ZRAM_PRIORITY"
if (( SWAPFILE_OK )); then
  printf '  • swapfile: %s di %s, prioritas %s\n' "$(bytes_human "$SWAP_BYTES")" "$SWAPFILE" "$SWAPFILE_PRIORITY"
else
  printf '  • swapfile: dilewati (filesystem/ruang tidak aman)\n'
fi
printf '  • swappiness: 100 (zram-first)\n'
read -r -p "Lanjutkan perubahan konfigurasi? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || die "Dibatalkan oleh pengguna."

# Back up config files before modifying them.
STAMP="$(date +%Y%m%d-%H%M%S)"
backup_file() {
  local f="$1"
  if sudo test -e "$f"; then sudo cp -a "$f" "${f}.backup-${STAMP}"; fi
}
backup_file "$ZRAM_CONFIG"
backup_file "$SYSCTL_CONFIG"
backup_file "$FSTAB"

# Configure zram-tools on Debian family when present; otherwise use systemd zram-generator.
ZRAM_METHOD=""
if has systemctl && { has zramctl || [[ "$PM" == "apt-get" ]]; }; then
  if [[ "$PM" == "apt-get" ]] && has systemctl; then
    ZRAM_METHOD="zramswap"
    sudo install -d -m 0755 /etc/default
    sudo tee "$ZRAM_CONFIG" >/dev/null <<EOF
# Managed by install-zram.sh
ALGO=${ZRAM_ALGORITHM}
PERCENT=${ZRAM_PERCENT}
PRIORITY=${ZRAM_PRIORITY}
EOF
  else
    ZRAM_METHOD="systemd-zram-generator"
    sudo install -d -m 0755 /etc/systemd
    ZRAM_RATIO="$(awk -v p="$ZRAM_PERCENT" 'BEGIN {printf "%.2f", p/100}' )"
    sudo tee /etc/systemd/zram-generator.conf >/dev/null <<EOF
# Managed by install-zram.sh
[zram0]
zram-size = min(ram * ${ZRAM_RATIO}, 8192)
compression-algorithm = ${ZRAM_ALGORITHM}
swap-priority = ${ZRAM_PRIORITY}
EOF
  fi
fi

# Tune swappiness with a managed sysctl file.
sudo tee "$SYSCTL_CONFIG" >/dev/null <<'EOF'
# Managed by install-zram.sh
vm.swappiness = 100
EOF

# Configure swapfile if safe; never overwrite an existing file or active swap.
if (( SWAPFILE_OK )); then
  if [[ -e "$SWAPFILE" ]]; then
    if [[ -n "$SWAPFILE_ACTIVE" ]]; then
      say "Swapfile $SWAPFILE sudah aktif; tidak dibuat ulang."
    else
      warn "$SWAPFILE sudah ada tetapi tidak aktif; tidak ditimpa."
      warn "Aktifkan atau periksa file itu secara manual sebelum menambah entri fstab."
      SWAPFILE_OK=0
    fi
  else
    say "Membuat swapfile $(bytes_human "$SWAP_BYTES")..."
    if has fallocate; then
      sudo fallocate -l "$SWAP_BYTES" "$SWAPFILE" || {
        warn "fallocate gagal; mencoba dd (bisa memerlukan waktu)."
        sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_BYTES / 1048576)) status=progress
      }
    else
      sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_BYTES / 1048576)) status=progress
    fi
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
  fi

  if [[ -e "$SWAPFILE" ]] && ! sudo grep -Eq "^[[:space:]]*${SWAPFILE//\//\\/}[[:space:]]" "$FSTAB"; then
    printf '%s none swap sw,pri=%s 0 0\n' "$SWAPFILE" "$SWAPFILE_PRIORITY" | sudo tee -a "$FSTAB" >/dev/null
  fi
fi

# Enable/configure zram service according to selected method.
if [[ "$ZRAM_METHOD" == "zramswap" ]]; then
  if has systemctl; then
    sudo systemctl enable --now zramswap.service || sudo systemctl restart zramswap.service || warn "zramswap service gagal start; periksa status service."
  fi
elif [[ "$ZRAM_METHOD" == "systemd-zram-generator" ]]; then
  sudo systemctl daemon-reload
  sudo systemctl start dev-zram0.swap || warn "dev-zram0.swap gagal start; periksa journalctl -u dev-zram0.swap."
else
  warn "Metode aktivasi zram otomatis tidak terdeteksi. Konfigurasi dasar belum tentu aktif; lihat petunjuk distro."
fi

sudo sysctl --system >/dev/null || warn "Sebagian sysctl gagal diterapkan."
if (( SWAPFILE_OK )) && [[ -e "$SWAPFILE" ]] && ! swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"; then
  sudo swapon "$SWAPFILE" || warn "Swapfile tidak dapat diaktifkan; periksa format/filesystem."
fi

say "Selesai. Status swap saat ini:"
swapon --show --bytes --output NAME,TYPE,SIZE,USED,PRIO || true
say "Cek zram: zramctl"
say "Cek service: systemctl status zramswap (Debian-family) atau systemctl status dev-zram0.swap"
say "File backup memakai akhiran .backup-${STAMP}"
say "Catatan: swapfile tidak otomatis membuat hibernasi berfungsi; hibernasi membutuhkan konfigurasi resume tersendiri."
