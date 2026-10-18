#!/usr/bin/env bash
# Portable Zsh developer terminal setup for common Linux distributions.
# Installs eza, fzf, zoxide, git, bat, btop, then adds managed config to ~/.zshrc.
set -Eeuo pipefail

PLUGIN_DIR="${ZSH_PLUGIN_DIR:-$HOME/.local/share/zsh/plugins}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
MARKER_BEGIN="# >>> portable-zsh-dev-setup >>>"
MARKER_END="# <<< portable-zsh-dev-setup <<<"

say()  { printf '\033[1;32m[zsh-dev]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[zsh-dev warning]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[zsh-dev error]\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

[[ "$(id -u)" -ne 0 ]] || die "Jalankan sebagai user biasa, bukan sudo. sudo hanya dipakai untuk instalasi paket."
mkdir -p "$HOME" "$(dirname "$ZSHRC")"

# Prefer the distro package manager. Package names vary between distributions.
PM=""
for candidate in apt-get dnf pacman zypper apk xbps-install emerge yum; do
  if has "$candidate"; then PM="$candidate"; break; fi
done

install_packages() {
  local requested=("$@")
  local pkgs=()
  local p

  case "$PM" in
    apt-get)
      # On Debian/Ubuntu, eza may not exist in older repository versions.
      for p in "${requested[@]}"; do
        case "$p" in eza) pkgs+=(eza) ;; bat) pkgs+=(bat) ;; *) pkgs+=("$p") ;; esac
      done
      sudo apt-get update
      # Install independently so one unavailable package doesn't block all others.
      for p in "${pkgs[@]}"; do
        if ! sudo apt-get install -y "$p"; then
          if [[ "$p" == "eza" ]]; then
            warn "eza tidak tersedia di repository ini; akan mencoba instalasi binari upstream."
          elif [[ "$p" == "bat" ]]; then
            warn "bat tidak tersedia dengan nama ini di repository; lewati paket ini."
          else
            warn "Paket '$p' gagal diinstal; lanjut ke paket berikutnya."
          fi
        fi
      done
      ;;
    dnf)
      for p in "${requested[@]}"; do
        case "$p" in bat) pkgs+=(bat) ;; *) pkgs+=("$p") ;; esac
      done
      for p in "${pkgs[@]}"; do sudo dnf install -y "$p" || warn "Paket '$p' gagal diinstal."; done
      ;;
    yum)
      for p in "${requested[@]}"; do
        case "$p" in eza|zoxide) warn "'$p' mungkin tidak tersedia di repository yum."; continue ;; *) sudo yum install -y "$p" || warn "Paket '$p' gagal diinstal." ;; esac
      done
      ;;
    pacman)
      sudo pacman -Sy --needed --noconfirm "${requested[@]}"
      ;;
    zypper)
      for p in "${requested[@]}"; do sudo zypper --non-interactive install "$p" || warn "Paket '$p' gagal diinstal."; done
      ;;
    apk)
      for p in "${requested[@]}"; do sudo apk add "$p" || warn "Paket '$p' gagal diinstal."; done
      ;;
    xbps-install)
      sudo xbps-install -Sy "${requested[@]}"
      ;;
    emerge)
      for p in "${requested[@]}"; do sudo emerge --ask=n "$p" || warn "Paket '$p' gagal diinstal."; done
      ;;
    *)
      die "Package manager tidak dikenali. Instal git, zsh, eza, fzf, zoxide, bat, dan btop manual, lalu jalankan ulang."
      ;;
  esac
}

# Some distros package bat as 'batcat'; install what the package manager provides.
if [[ -z "$PM" ]]; then die "Tidak menemukan package manager yang didukung."; fi
say "Package manager terdeteksi: $PM"

# Install only packages that are not already available.
NEED=()
for p in git fzf zoxide btop; do has "$p" || NEED+=("$p"); done
has eza || NEED+=(eza)
if ! has bat && ! has batcat; then NEED+=(bat); fi

if ((${#NEED[@]})); then
  say "Menginstal paket yang belum tersedia: ${NEED[*]}"
  install_packages "${NEED[@]}"
else
  say "Semua tool pilihan sudah terpasang."
fi

# Optional portable fallback for eza when it is missing after package install.
if ! has eza; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) asset_arch="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) asset_arch="aarch64-unknown-linux-gnu" ;;
    *)
      warn "Arsitektur $arch tidak didukung untuk fallback eza. Alias ls akan fallback ke ls biasa."
      asset_arch=""
      ;;
  esac
  if [[ -n "$asset_arch" ]] && has curl && has tar; then
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir:-}"' EXIT
    url="https://github.com/eza-community/eza/releases/latest/download/eza_${asset_arch}.tar.gz"
    say "Repository distro tidak menyediakan eza; mencoba binari upstream."
    if curl -fL --retry 2 "$url" -o "$tmpdir/eza.tar.gz" && tar -xzf "$tmpdir/eza.tar.gz" -C "$tmpdir"; then
      mkdir -p "$HOME/.local/bin"
      if [[ -f "$tmpdir/eza" ]]; then
        install -m 0755 "$tmpdir/eza" "$HOME/.local/bin/eza"
      else
        candidate="$(find "$tmpdir" -type f -name eza -perm -u+x -print -quit)"
        [[ -n "$candidate" ]] && install -m 0755 "$candidate" "$HOME/.local/bin/eza"
      fi
      export PATH="$HOME/.local/bin:$PATH"
    else
      warn "Fallback eza gagal. Alias akan menggunakan ls biasa hingga eza dipasang."
    fi
    rm -rf "$tmpdir"
    trap - EXIT
  fi
fi

# Ensure user's local bin is on PATH in the generated configuration.
if [[ -f "$ZSHRC" ]] && ! grep -Fq "$MARKER_BEGIN" "$ZSHRC"; then
  backup="$ZSHRC.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$ZSHRC" "$backup"
  say "Backup konfigurasi lama: $backup"
fi
touch "$ZSHRC"
tmp="$(mktemp)"
awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
  $0 == begin {skip=1; next}
  $0 == end {skip=0; next}
  !skip {print}
' "$ZSHRC" > "$tmp"

cat >> "$tmp" <<'ZSH_CONFIG'

# >>> portable-zsh-dev-setup >>>
# Managed by portable-zsh-dev-setup.sh. This block is replaced safely on reruns.

# User-local binaries (e.g. portable eza fallback).
export PATH="$HOME/.local/bin:$PATH"

# eza: modern ls with file-type icons. Requires a Nerd Font in the terminal.
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --group-directories-first'
  alias la='eza -a --icons=auto --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto'
  alias lS='eza -lah --sort=size --icons=auto --group-directories-first'
else
  alias ls='command ls --color=auto'
  alias ll='command ls -lah --color=auto'
  alias la='command ls -A --color=auto'
  alias lt='command find . -maxdepth 2 -print'
  alias lS='command ls -lahS --color=auto'
fi

# systemctl shortcut: sc start nginx, sc status nginx, sc list, sc failed, etc.
sc() {
  if (( $# == 0 )); then
    print -u2 'Usage: sc {start|stop|restart|status|enable|disable|reload|list|failed} [unit]'
    return 2
  fi
  case "$1" in
    start|stop|restart|status|enable|disable|reload)
      if (( $# < 2 )); then
        print -u2 "Usage: sc $1 <service>"
        return 2
      fi
      sudo systemctl "$@"
      ;;
    list)
      sudo systemctl list-units --type=service --all
      ;;
    failed)
      sudo systemctl --failed
      ;;
    *)
      print -u2 "Operasi sc tidak dikenal: $1"
      print -u2 'Pilih: start, stop, restart, status, enable, disable, reload, list, failed'
      return 2
      ;;
  esac
}

# Short Git aliases.
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git pull'
alias gP='git push'
alias gd='git diff'
alias gl='git log --oneline --decorate -15'
alias gb='git branch'
alias gco='git checkout'

# Small system diagnostics.
alias dfh='df -h'
alias duh='du -sh'
alias mem='free -h'
alias ports='ss -tulpn'
alias myip='ip -brief address'
alias psg='ps aux | grep -i'

# Tool integrations.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if (( $+commands[fzf] )); then
  # fzf key bindings/completion are installed by many distro packages in standard paths.
  for fzf_script in \
    /usr/share/fzf/key-bindings.zsh \
    /usr/share/fzf/completion.zsh \
    /usr/share/doc/fzf/examples/key-bindings.zsh \
    /usr/share/doc/fzf/examples/completion.zsh; do
    [[ -r "$fzf_script" ]] && source "$fzf_script"
  done
fi

# Oh My Posh initialization is intentionally left untouched; existing prompt setup remains in your original .zshrc.
# <<< portable-zsh-dev-setup <<<
ZSH_CONFIG

mv "$tmp" "$ZSHRC"

say "Konfigurasi selesai: $ZSHRC"
say "Tool yang terdeteksi:"
for cmd in eza fzf zoxide git bat batcat btop; do
  if has "$cmd"; then printf '  ✓ %s -> %s\n' "$cmd" "$(command -v "$cmd")"; fi
done
say "Aktifkan konfigurasi dengan: exec zsh"
say "Ikon eza memerlukan Nerd Font. Jika ikon tidak tampil, atur font terminal ke Nerd Font."
say "Untuk menjadikan Zsh default (opsional): chsh -s \"$(command -v zsh)\""
