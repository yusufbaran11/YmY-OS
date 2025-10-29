#!/bin/bash

# Kolay Linux Dağıtımı Oluşturucu
# Ubuntu tabanlı özelleştirilmiş bir dağıtım yapılandırması

set -e

DISTRO_NAME="YmY-OS"
DISTRO_VERSION="1.0"
BUILD_DIR="$HOME/distro-build"

echo "🚀 $DISTRO_NAME Dağıtımı Oluşturuluyor..."

# Gerekli araçları yükle
install_tools() {
    echo "📦 Gerekli araçlar kuruluyor..."
    sudo apt-get update
    sudo apt-get install -y \
        debootstrap \
        squashfs-tools \
        xorriso \
        isolinux \
        syslinux-efi \
        grub-pc-bin \
        grub-efi-amd64-bin \
        mtools
}

# Temel sistem oluştur
create_base_system() {
    echo "🔧 Temel sistem oluşturuluyor..."
    
    # Önceki build klasörünü temizle
    if [ -d "$BUILD_DIR" ]; then
        echo "Eski build klasörü temizleniyor..."
        sudo rm -rf "$BUILD_DIR"
    fi
    
    mkdir -p "$BUILD_DIR"/{chroot,image/{casper,isolinux,install}}
    
    # Ubuntu temel sistemini indir (daha detaylı log ile)
    echo "Ubuntu Noble (24.04) base sistemi indiriliyor..."
    sudo debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --verbose \
        noble \
        "$BUILD_DIR/chroot" \
        http://archive.ubuntu.com/ubuntu/ || {
            echo "❌ Debootstrap hatası! Alternatif mirror deneniyor..."
            sudo rm -rf "$BUILD_DIR/chroot"
            sudo debootstrap \
                --arch=amd64 \
                --variant=minbase \
                --verbose \
                noble \
                "$BUILD_DIR/chroot" \
                http://tr.archive.ubuntu.com/ubuntu/
        }
    
    echo "$DISTRO_NAME" | sudo tee "$BUILD_DIR/chroot/etc/hostname"
}

# Chroot ortamına gir ve yapılandır
configure_system() {
    echo "⚙️  Sistem yapılandırılıyor..."
    
    # DNS ayarları
    sudo cp /etc/resolv.conf "$BUILD_DIR/chroot/etc/resolv.conf"
    
    # Chroot içinde çalışacak script
    cat > /tmp/chroot_config.sh << 'CHROOT_EOF'
#!/bin/bash

export HOME=/root
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Depoları yapılandır
cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF

apt-get update
apt-get install -y --no-install-recommends \
    linux-generic \
    casper \
    lupin-casper \
    discover \
    laptop-detect \
    os-prober \
    network-manager \
    net-tools \
    wireless-tools \
    wpagui \
    locales \
    grub-common \
    grub-gfxpayload-lists \
    grub-pc \
    grub-pc-bin \
    grub2-common

# Masaüstü ortamı - GNOME (modern ve kullanıcı dostu)
apt-get install -y \
    ubuntu-desktop-minimal \
    gnome-shell \
    gnome-shell-extensions \
    gnome-shell-extension-manager \
    gnome-tweaks \
    chrome-gnome-shell \
    firefox \
    thunderbird \
    libreoffice \
    vlc \
    gimp \
    rhythmbox \
    gnome-software \
    gnome-software-plugin-flatpak \
    flatpak

# Kullanıcı dostu GNOME eklentileri
apt-get install -y \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-desktop-icons-ng \
    gnome-shell-extension-dash-to-panel \
    gnome-shell-extension-arc-menu \
    gnome-shell-extension-blur-my-shell

# Sistem araçları
apt-get install -y \
    gnome-disk-utility \
    gnome-system-monitor \
    dconf-editor \
    baobab \
    file-roller \
    gedit \
    gnome-calculator \
    gnome-screenshot \
    gnome-terminal

# Türkçe dil desteği
apt-get install -y \
    language-pack-tr \
    language-pack-gnome-tr \
    firefox-locale-tr \
    libreoffice-l10n-tr

# Locale ayarları
locale-gen tr_TR.UTF-8
update-locale LANG=tr_TR.UTF-8

# Kullanıcı oluştur
useradd -m -s /bin/bash kullanici
echo "kullanici:KolayLinux2024!" | chpasswd
usermod -aG sudo kullanici

# Hoşgeldin mesajı
cat > /etc/issue << EOF
\l

YmY OS'a Hoş Geldiniz!
Modern, basit ve kullanıcı dostu Linux dağıtımı.

Varsayılan kullanıcı: kullanici
Varsayılan şifre: Ymy12345!

EOF

# GNOME eklentilerini otomatik aktifleştir
mkdir -p /home/kullanici/.config/autostart
cat > /home/kullanici/.config/autostart/enable-extensions.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Enable GNOME Extensions
Exec=bash -c "sleep 5 && gnome-extensions enable dash-to-panel@jderose9.github.com && gnome-extensions enable arcmenu@arcmenu.com && gnome-extensions enable blur-my-shell@aunetx && gnome-extensions enable ding@rastersoft.com && gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

chown -R kullanici:kullanici /home/kullanici/.config

# GDM otomatik giriş ayarı
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=kullanici

[security]

[xdmcp]

[chooser]

[debug]
EOF

# Temizlik
apt-get clean
rm -rf /tmp/* ~/.bash_history
CHROOT_EOF

    # Script'i chroot'a kopyala ve çalıştır
    sudo cp /tmp/chroot_config.sh "$BUILD_DIR/chroot/tmp/"
    sudo chmod +x "$BUILD_DIR/chroot/tmp/chroot_config.sh"
    sudo chroot "$BUILD_DIR/chroot" /tmp/chroot_config.sh
}

# ISO imajını oluştur
create_iso() {
    echo "💿 ISO imajı oluşturuluyor..."
    
    # Kernel ve initrd'yi kopyala
    sudo cp "$BUILD_DIR/chroot/boot/vmlinuz-"* "$BUILD_DIR/image/casper/vmlinuz"
    sudo cp "$BUILD_DIR/chroot/boot/initrd.img-"* "$BUILD_DIR/image/casper/initrd"
    
    # Manifest oluştur
    sudo chroot "$BUILD_DIR/chroot" dpkg-query -W --showformat='${Package} ${Version}\n' | \
        sudo tee "$BUILD_DIR/image/casper/filesystem.manifest"
    
    # SquashFS oluştur
    echo "📦 Dosya sistemi sıkıştırılıyor (bu biraz zaman alabilir)..."
    sudo mksquashfs "$BUILD_DIR/chroot" "$BUILD_DIR/image/casper/filesystem.squashfs" \
        -comp xz -b 1M
    
    # ISO bilgileri
    cat > "$BUILD_DIR/image/README.diskdefines" << EOF
#define DISKNAME  $DISTRO_NAME $DISTRO_VERSION
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    
    # GRUB yapılandırması
    mkdir -p "$BUILD_DIR/image/boot/grub"
    cat > "$BUILD_DIR/image/boot/grub/grub.cfg" << 'EOF'
set default="0"
set timeout=10

menuentry "$DISTRO_NAME - Canlı Sistem" {
    linux /casper/vmlinuz boot=casper quiet splash locale=tr_TR.UTF-8
    initrd /casper/initrd
}

menuentry "$DISTRO_NAME - Güvenli Mod" {
    linux /casper/vmlinuz boot=casper xforcevesa quiet splash locale=tr_TR.UTF-8
    initrd /casper/initrd
}
EOF
    
    # ISO oluştur
    cd "$BUILD_DIR/image"
    sudo grub-mkrescue -o "$HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso" .
    
    echo "✅ ISO başarıyla oluşturuldu: $HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso"
}

# Ana fonksiyon
main() {
    echo "==================================="
    echo "$DISTRO_NAME Dağıtım Oluşturucu"
    echo "==================================="
    echo ""
    
    install_tools
    create_base_system
    configure_system
    create_iso
    
    echo ""
    echo "🎉 İşlem tamamlandı!"
    echo "ISO dosyanız: $HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso"
    echo ""
    echo "Bu ISO'yu VirtualBox veya VMware'de test edebilirsiniz."
}

main