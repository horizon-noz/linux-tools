# Linux Terminal Setup Scripts

Kumpulan script Bash untuk menyiapkan lingkungan terminal Linux dengan Zsh, plugin produktivitas, tampilan file berikon, shortcut administrasi sistem, serta konfigurasi zram dan swapfile.

Script dibuat agar bisa digunakan di berbagai distro Linux yang umum. Dukungan paket dan layanan tetap bergantung pada distro, versi repository, filesystem, dan init system yang digunakan.

## Daftar Script

### `portable-zsh-setup.sh`

Instalasi awal Zsh dan plugin dasar:

- `zsh-autosuggestions` — saran perintah dari riwayat shell.
- `zsh-syntax-highlighting` — pewarnaan sintaks perintah.
- `zsh-completions` — tambahan completion.
- `zsh-history-substring-search` — pencarian riwayat berdasarkan teks.

Script membuat backup `.zshrc` yang sudah ada sebelum mengubah konfigurasi dan mempertahankan konfigurasi di luar blok yang dikelolanya.

### `portable-zsh-dev-setup.sh`

Menambahkan fitur untuk terminal harian dan workflow developer:

- **eza** — pengganti `ls` dengan warna dan ikon.
- **fzf** — pencarian interaktif.
- **zoxide** — navigasi direktori berdasarkan riwayat.
- **Git aliases** — shortcut untuk perintah Git.
- **bat** — pembaca file dengan syntax highlighting.
- **btop** — monitor resource sistem.
- **`sc`** — shortcut untuk operasi `systemctl`.
- Alias diagnostik dasar seperti `mem`, `dfh`, `ports`, dan `myip`.

Contoh perintah setelah konfigurasi:

```bash
ls
ll
la
lt
lS

sc start nginx
sc stop nginx
sc restart nginx
sc status nginx
sc enable nginx
sc disable nginx
sc reload nginx
sc list
sc failed

gs       # git status
gp       # git pull
gP       # git push
mem      # penggunaan RAM
ports    # port yang sedang listen
btop     # monitor sistem
```

Ikon eza memerlukan font terminal yang mendukung glyph Nerd Font. Jika `eza` tidak tersedia di repository distro, script mencoba fallback binari upstream pada arsitektur Linux tertentu jika dependensinya tersedia.

### `install-zram.sh`

Script untuk membantu mengatur zram dan swapfile berdasarkan kondisi sistem:

- Mendeteksi RAM melalui `/proc/meminfo`.
- Mendeteksi filesystem root, kapasitas, dan ruang kosong.
- Memeriksa swap aktif sebelum membuat swapfile.
- Menghitung ukuran zram dan swapfile dengan batas tertentu.
- Meminta konfirmasi sebelum perubahan konfigurasi.
- Membuat backup konfigurasi sistem yang akan diubah.
- Mengatur `vm.swappiness`.
- Menghindari pembuatan swapfile generik pada filesystem tertentu, termasuk Btrfs.

> **Penting:** perilaku layanan zram berbeda antar distro. Periksa hasil aktivasi setelah menjalankan script. Script ini tidak mengatur hibernasi atau konfigurasi resume.

## Persyaratan

- Linux dengan Bash.
- Akses `sudo` untuk instalasi paket dan perubahan konfigurasi sistem.
- Koneksi internet untuk mengunduh plugin atau paket yang diperlukan.
- Package manager yang didukung oleh script terkait.
- Untuk ikon terminal, gunakan Nerd Font yang sesuai.

Package manager yang dikenali pada script meliputi beberapa di antara `apt-get`, `dnf`, `pacman`, `zypper`, `apk`, `xbps-install`, `emerge`, dan `yum`. Tidak semua paket tersedia pada semua distro atau versi repository.

## Instalasi

Unduh atau clone repository, lalu masuk ke direktori project.

Jadikan script executable:

```bash
chmod +x portable-zsh-setup.sh
chmod +x portable-zsh-dev-setup.sh
chmod +x install-zram.sh
```

### 1. Instal Zsh dan plugin dasar

```bash
./portable-zsh-setup.sh
```

### 2. Pasang tool terminal developer

```bash
./portable-zsh-dev-setup.sh
```

Muat ulang Zsh setelah konfigurasi:

```bash
exec zsh
```

Jika ingin menjadikan Zsh sebagai shell default, jalankan secara terpisah:

```bash
chsh -s "$(command -v zsh)"
```

Logout lalu login kembali jika diperlukan.

### 3. Konfigurasi zram dan swapfile

```bash
./install-zram.sh
```

Script akan menampilkan rencana konfigurasi dan meminta konfirmasi sebelum melanjutkan.

Ukuran swapfile dapat ditentukan melalui variabel lingkungan:

```bash
SWAPFILE_SIZE=4G ./install-zram.sh
```

Target persentase zram dapat diubah, misalnya:

```bash
ZRAM_PERCENT=75 ./install-zram.sh
```

Kedua opsi dapat digabung:

```bash
ZRAM_PERCENT=75 SWAPFILE_SIZE=4G ./install-zram.sh
```

Periksa hasil konfigurasi swap dengan:

```bash
free -h
swapon --show
zramctl
```

## Backup dan konfigurasi

Script Zsh menambahkan blok konfigurasi yang dikelola secara khusus di `.zshrc`. Saat dijalankan ulang, blok tersebut diperbarui agar konfigurasi tidak terduplikasi. Konfigurasi di luar blok tersebut dipertahankan.

Sebelum perubahan, script membuat backup dengan akhiran timestamp jika file konfigurasi sudah ada.

Script `install-zram.sh` juga membuat backup untuk file sistem yang hendak diubah. Lokasi dan nama backup ditampilkan atau dapat diperiksa pada sistem setelah eksekusi.

Tetap tinjau script sebelum menjalankannya, khususnya karena script dapat memasang paket, mengubah konfigurasi shell, mengubah `/etc/fstab`, dan mengaktifkan swap.

## Catatan kompatibilitas dan keamanan

- Script bersifat best-effort lintas distro, bukan jaminan kompatibilitas universal.
- Nama paket, lokasi konfigurasi, service manager, dan metode aktivasi zram dapat berbeda antar distro.
- Script zram memerlukan pemeriksaan manual jika layanan tidak aktif setelah instalasi.
- Swapfile pada Btrfs memerlukan prosedur khusus; script ini melewatinya untuk menghindari konfigurasi yang tidak aman.
- Swapfile tidak otomatis mengaktifkan hibernasi. Konfigurasi resume dan persyaratan hibernasi perlu ditangani secara terpisah.
- Jalankan script sebagai user biasa; jangan menambahkan `sudo` di depan script.
- Buat backup data penting dan tinjau isi script sebelum digunakan pada mesin produksi.

## Lisensi

Belum ditentukan. Tambahkan file `LICENSE` jika repository akan dibagikan atau digunakan oleh orang lain.
