#!/usr/bin/env bash
# setup-github-ssh.sh
# Portable interactive setup for Git identity, custom-named SSH key, and Zsh Keychain.
set -Eeuo pipefail

MARKER_BEGIN="# >>> github-ssh-keychain-setup >>>"
MARKER_END="# <<< github-ssh-keychain-setup <<<"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SSH_DIR="$HOME/.ssh"

say()  { printf '\033[1;32m[github-ssh]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warning]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

prompt_value() {
  local prompt="$1" default="${2:-}" reply=""
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply
    printf '%s' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    printf '%s' "$reply"
  fi
}

[[ "$(id -u)" -ne 0 ]] || die "Jalankan sebagai user biasa, bukan dengan sudo."
[[ -t 0 ]] || die "Script ini interaktif; jalankan langsung di terminal."

# Identify package manager for optional dependency installation.
PM=""
for candidate in apt-get dnf pacman zypper apk xbps-install emerge yum; do
  if has "$candidate"; then PM="$candidate"; break; fi
done

install_dependencies() {
  local packages=()
  case "$PM" in
    apt-get) packages=(git openssh-client keychain); sudo apt-get update; sudo apt-get install -y "${packages[@]}" ;;
    dnf) packages=(git openssh-clients keychain); sudo dnf install -y "${packages[@]}" ;;
    yum) packages=(git openssh-clients keychain); sudo yum install -y "${packages[@]}" ;;
    pacman) packages=(git openssh keychain); sudo pacman -S --needed --noconfirm "${packages[@]}" ;;
    zypper) packages=(git openssh keychain); sudo zypper --non-interactive install "${packages[@]}" ;;
    apk) packages=(git openssh-client keychain); sudo apk add "${packages[@]}" ;;
    xbps-install) packages=(git openssh keychain); sudo xbps-install -Sy "${packages[@]}" ;;
    emerge) packages=(dev-vcs/git net-misc/openssh app-admin/keychain); sudo emerge --ask=n "${packages[@]}" ;;
    *) warn "Package manager tidak dikenali; instal git, OpenSSH, dan keychain secara manual." ; return 1 ;;
  esac
}

NEED_INSTALL=0
for cmd in git ssh-keygen ssh ssh-add; do
  has "$cmd" || NEED_INSTALL=1
done
if ! has keychain; then NEED_INSTALL=1; fi

if (( NEED_INSTALL )); then
  if [[ -z "$PM" ]]; then
    warn "Package manager tidak dikenali."
  elif [[ "${AUTO_INSTALL:-}" == "1" ]]; then
    install_dependencies || warn "Instalasi dependensi tidak sepenuhnya berhasil."
  else
    read -r -p "Git/OpenSSH/Keychain belum lengkap. Coba instal lewat '$PM'? [Y/n] " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      install_dependencies || warn "Instalasi dependensi tidak sepenuhnya berhasil."
    fi
  fi
fi

has git || die "Git belum tersedia. Instal Git lalu jalankan ulang script."
has ssh-keygen || die "ssh-keygen belum tersedia. Instal OpenSSH client lalu jalankan ulang."
has ssh || die "Perintah ssh belum tersedia. Instal OpenSSH client lalu jalankan ulang."

# Configure Git identity only when the values are currently missing.
current_name="$(git config --global --get user.name 2>/dev/null || true)"
if [[ -z "${current_name//[[:space:]]/}" ]]; then
  git_name="$(prompt_value 'Nama Git (user.name)')"
  [[ -n "${git_name//[[:space:]]/}" ]] || die "Nama Git tidak boleh kosong."
  git config --global user.name "$git_name"
  say "Git user.name disetel."
else
  say "Git user.name sudah disetel: $current_name (tidak diubah)."
fi

current_email="$(git config --global --get user.email 2>/dev/null || true)"
if [[ -z "${current_email//[[:space:]]/}" ]]; then
  git_email="$(prompt_value 'Email Git (user.email)')"
  [[ "$git_email" == *@* && "$git_email" != *@*' '* ]] || die "Format email terlihat tidak valid."
  git config --global user.email "$git_email"
  say "Git user.email disetel."
else
  git_email="$current_email"
  say "Git user.email sudah disetel: $current_email (tidak diubah)."
fi

# Create/choose an SSH key using a custom basename.
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
default_key="github_ed25519"
key_name="$(prompt_value 'Nama file SSH key (tanpa path; disimpan di ~/.ssh)' "$default_key")"
[[ -n "$key_name" ]] || die "Nama file key tidak boleh kosong."
[[ "$key_name" =~ ^[A-Za-z0-9._-]+$ && "$key_name" != "." && "$key_name" != ".." ]] || die "Gunakan nama file saja dengan huruf, angka, titik, garis bawah, atau tanda hubung (tanpa path/spasi)."

KEY_PATH="$SSH_DIR/$key_name"
PUB_PATH="${KEY_PATH}.pub"

if [[ -e "$KEY_PATH" || -e "$PUB_PATH" ]]; then
  if [[ -f "$KEY_PATH" && -f "$PUB_PATH" ]]; then
    read -r -p "Key $KEY_PATH sudah ada. Gunakan key ini? [Y/n] " use_existing
    if [[ "$use_existing" =~ ^[Nn]$ ]]; then
      die "Pilih nama file lain dengan menjalankan ulang script."
    fi
    say "Menggunakan SSH key yang sudah ada."
  else
    die "File key hanya sebagian sudah ada ($KEY_PATH atau $PUB_PATH). Tidak ada file yang ditimpa. Pilih nama lain atau periksa file tersebut."
  fi
else
  say "Membuat SSH key Ed25519: $KEY_PATH"
  say "ssh-keygen akan meminta passphrase. Passphrase disarankan; tekan Enter dua kali hanya jika memang ingin tanpa passphrase."
  ssh-keygen -t ed25519 -C "$git_email" -f "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  chmod 644 "$PUB_PATH"
fi

# Add/rewrite only this script's managed Keychain block in ~/.zshrc.
mkdir -p "$(dirname "$ZSHRC")"
if [[ -f "$ZSHRC" ]] && ! grep -Fq "$MARKER_BEGIN" "$ZSHRC"; then
  backup="$ZSHRC.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$ZSHRC" "$backup"
  say "Backup .zshrc dibuat: $backup"
fi
touch "$ZSHRC"
tmp="$(mktemp)"
awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
  $0 == begin { skip=1; next }
  $0 == end { skip=0; next }
  !skip { print }
' "$ZSHRC" > "$tmp"

{
  printf '\n%s\n' "$MARKER_BEGIN"
  printf '%s\n' '# Start/reuse ssh-agent through Keychain and load this key automatically in Zsh.'
  printf '%s\n' 'if command -v keychain >/dev/null 2>&1; then'
  printf '  eval "$(keychain --eval --quiet --agents ssh "%s")"\n' "$KEY_PATH"
  printf '%s\n' 'fi'
  printf '%s\n' "$MARKER_END"
} >> "$tmp"
mv "$tmp" "$ZSHRC"

# Load into the current agent too, if Keychain is present.
if has keychain; then
  say "Menyiapkan Keychain untuk sesi terminal saat ini..."
  # keychain may prompt to unlock an encrypted key; that is expected.
  eval "$(keychain --eval --quiet --agents ssh "$KEY_PATH")"
  if has ssh-add; then ssh-add "$KEY_PATH" 2>/dev/null || true; fi
else
  warn "Keychain belum terpasang. Blok .zshrc sudah ditambahkan, tetapi otomatisasi aktif setelah Keychain diinstal."
fi

say "Git dan SSH key sudah disiapkan."
printf '\nPublic key (yang boleh ditambahkan ke GitHub):\n'
printf '%s\n' "----------------------------------------------------------------"
cat "$PUB_PATH"
printf '%s\n' "----------------------------------------------------------------"

printf '\nLangkah berikutnya:\n'
printf '1. Buka https://github.com/settings/keys\n'
printf '2. Pilih New SSH key, beri title untuk perangkat ini, dan pilih Authentication Key.\n'
printf '3. Tempel isi public key di atas (file: %s).\n' "$PUB_PATH"
printf '4. Muat konfigurasi: source %q\n' "$ZSHRC"
printf '5. Tes koneksi: ssh -T git@github.com\n'
printf '\nJangan pernah mengunggah atau membagikan private key: %s\n' "$KEY_PATH"

# Print remote URL conversion hint, without changing any repository automatically.
printf '\nJika repository masih menggunakan HTTPS, di direktori repository jalankan:\n'
printf '%s\n' 'git remote -v'
printf '%s\n' 'git remote set-url origin git@github.com:OWNER/REPOSITORY.git'
