#!/bin/bash

# YmY OS Dağıtım Oluşturucu - Tam Çalışan Versiyon
# Ubuntu 24.04 LTS tabanlı özelleştirilmiş dağıtım

set -e

DISTRO_NAME="YmY-OS"
DISTRO_VERSION="1.0"
BUILD_DIR="$HOME/distro-build"
LIVE_USER="live"
LIVE_PASS="YmY111317!"

echo "🚀 $DISTRO_NAME Dağıtımı Oluşturuluyor..."

# Gerekli araçları yükle
install_tools() {
    echo "📦 Gerekli araçlar kuruluyor..."
    sudo apt-get update
    sudo apt-get install -y \
        debootstrap \
        squashfs-tools \
        xorriso \
        syslinux-utils \
        grub-pc-bin \
        grub-efi-amd64-bin \
        mtools \
        grub-common
}

# Temel sistem oluştur
create_base_system() {
    echo "🔧 Temel sistem oluşturuluyor..."
    
    if [ -d "$BUILD_DIR" ]; then
        echo "Eski build klasörü temizleniyor..."
        sudo rm -rf "$BUILD_DIR"
    fi
    
    mkdir -p "$BUILD_DIR"/{chroot,image/{casper,isolinux,install,boot/grub}}
    
    echo "Ubuntu Noble (24.04) base sistemi indiriliyor..."
    sudo debootstrap \
        --arch=amd64 \
        --variant=minbase \
        noble \
        "$BUILD_DIR/chroot" \
        http://archive.ubuntu.com/ubuntu/
    
    echo "$DISTRO_NAME" | sudo tee "$BUILD_DIR/chroot/etc/hostname"
}

# Chroot ortamına gir ve yapılandır
configure_system() {
    echo "⚙️  Sistem yapılandırılıyor..."
    
    sudo cp /etc/resolv.conf "$BUILD_DIR/chroot/etc/resolv.conf"
    
    # Tam chroot yapılandırma scripti
    cat > /tmp/chroot_config.sh << 'CHROOT_EOF'
#!/bin/bash

export HOME=/root
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

echo "🔄 Depoları yapılandırıyor..."
cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF

echo "📦 Paket listesi güncelleniyor..."
apt-get update

echo "🐧 Temel sistem paketleri kuruluyor..."
apt-get install -y --no-install-recommends \
    linux-generic \
    linux-headers-generic \
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
    grub2-common \
    grub-efi-amd64

echo "🖥️ GNOME masaüstü ortamı kuruluyor..."
apt-get install -y \
    ubuntu-desktop-minimal \
    gnome-shell \
    gnome-shell-extensions \
    gnome-shell-extension-manager \
    gnome-tweaks \
    chrome-gnome-shell

echo "📱 Uygulama paketleri kuruluyor..."
apt-get install -y \
    firefox \
    thunderbird \
    libreoffice \
    vlc \
    gimp \
    rhythmbox \
    gnome-software \
    gnome-disk-utility \
    gnome-system-monitor \
    dconf-editor \
    baobab \
    file-roller \
    gedit \
    gnome-calculator \
    gnome-screenshot \
    gnome-terminal

echo "🌍 Türkçe dil desteği kuruluyor..."
apt-get install -y \
    language-pack-tr \
    language-pack-gnome-tr \
    firefox-locale-tr \
    libreoffice-l10n-tr

echo "🔤 Locale ayarları yapılıyor..."
locale-gen tr_TR.UTF-8
update-locale LANG=tr_TR.UTF-8

echo "👤 Kullanıcı oluşturuluyor..."
useradd -m -s /bin/bash live
echo "live:YmY111317!" | chpasswd
usermod -aG sudo live

echo "📝 Hoşgeldin mesajı oluşturuluyor..."
cat > /etc/issue << EOF

YmY OS'a Hoş Geldiniz!
Modern, basit ve kullanıcı dostu Linux dağıtımı.

Varsayılan kullanıcı: live
Varsayılan şifre: YmY111317!

EOF

echo "🎨 GNOME eklentileri yapılandırılıyor..."
mkdir -p /home/live/.config/autostart
cat > /home/live/.config/autostart/welcome.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=YmY OS Welcome
Exec=zenity --info --text="YmY OS'a Hoş Geldiniz!\n\nKullanıcı: live\nŞifre: YmY111317!" --width=300
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

chown -R live:live /home/live/.config

echo "🖼️ GDM otomatik giriş ayarlanıyor..."
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=live

[security]

[xdmcp]

[chooser]

[debug]
EOF

echo "🔧 Initramfs güncelleniyor..."
update-initramfs -c -k all

echo "🧹 Temizlik yapılıyor..."
apt-get clean
rm -rf /tmp/* ~/.bash_history /var/lib/apt/lists/*
find /var/log -type f -delete

echo "✅ Chroot yapılandırması tamamlandı!"
CHROOT_EOF

    sudo cp /tmp/chroot_config.sh "$BUILD_DIR/chroot/tmp/"
    sudo chmod +x "$BUILD_DIR/chroot/tmp/chroot_config.sh"
    
    echo "🔗 Sistem dizinleri bağlanıyor..."
    sudo mount --bind /dev "$BUILD_DIR/chroot/dev"
    sudo mount --bind /sys "$BUILD_DIR/chroot/sys"
    sudo mount --bind /proc "$BUILD_DIR/chroot/proc"
    
    echo "⚙️ Chroot içinde yapılandırma çalıştırılıyor..."
    sudo chroot "$BUILD_DIR/chroot" /tmp/chroot_config.sh
    
    echo "🔓 Sistem dizinleri ayrılıyor..."
    sudo umount "$BUILD_DIR/chroot/dev" || true
    sudo umount "$BUILD_DIR/chroot/sys" || true
    sudo umount "$BUILD_DIR/chroot/proc" || true
}

# ISO imajını oluştur
create_iso() {
    echo "💿 ISO imajı oluşturuluyor..."
    
    echo "🔍 Kernel ve initrd dosyaları aranıyor..."
    VMLINUZ_FILE=$(sudo find "$BUILD_DIR/chroot/boot/" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n 1)
    INITRD_FILE=$(sudo find "$BUILD_DIR/chroot/boot/" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n 1)
    
    if [ -z "$VMLINUZ_FILE" ]; then
        echo "❌ Kernel dosyası bulunamadı!"
        echo "Boot klasörü içeriği:"
        sudo ls -la "$BUILD_DIR/chroot/boot/"
        exit 1
    fi
    
    if [ -z "$INITRD_FILE" ]; then
        echo "❌ Initrd dosyası bulunamadı!"
        echo "Boot klasörü içeriği:"
        sudo ls -la "$BUILD_DIR/chroot/boot/"
        exit 1
    fi
    
    echo "✅ Kernel bulundu: $VMLINUZ_FILE"
    echo "✅ Initrd bulundu: $INITRD_FILE"
    
    sudo cp "$VMLINUZ_FILE" "$BUILD_DIR/image/casper/vmlinuz"
    sudo cp "$INITRD_FILE" "$BUILD_DIR/image/casper/initrd"
    
    echo "📋 Manifest oluşturuluyor..."
    sudo chroot "$BUILD_DIR/chroot" dpkg-query -W --showformat='${Package} ${Version}\n' | \
        sudo tee "$BUILD_DIR/image/casper/filesystem.manifest"
    
    echo "📦 SquashFS oluşturuluyor (bu 20-30 dakika sürebilir)..."
    sudo mksquashfs "$BUILD_DIR/chroot" "$BUILD_DIR/image/casper/filesystem.squashfs" \
        -comp xz -b 1M -e boot dev proc sys
    
    echo "📄 ISO bilgileri oluşturuluyor..."
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
    
    echo "💾 Bootloader dosyaları kopyalanıyor..."
    sudo cp /usr/lib/syslinux/modules/bios/isolinux.bin "$BUILD_DIR/image/isolinux/"
    sudo cp /usr/lib/syslinux/modules/bios/vesamenu.c32 "$BUILD_DIR/image/isolinux/"
    
    echo "⚙️ ISOLINUX yapılandırılıyor..."
    cat > "$BUILD_DIR/image/isolinux/isolinux.cfg" << EOF
UI vesamenu.c32

MENU TITLE $DISTRO_NAME Live
DEFAULT live

LABEL live
  menu label ^$DISTRO_NAME - Canlı Sistem
  kernel /casper/vmlinuz
  append initrd=/casper/initrd boot=casper quiet splash locale=tr_TR.UTF-8

LABEL safe
  menu label ^$DISTRO_NAME - Güvenli Mod
  kernel /casper/vmlinuz
  append initrd=/casper/initrd boot=casper xforcevesa quiet splash locale=tr_TR.UTF-8
EOF

    echo "⚙️ GRUB yapılandırılıyor..."
    cat > "$BUILD_DIR/image/boot/grub/grub.cfg" << EOF
set default="0"
set timeout=5

menuentry "$DISTRO_NAME - Canlı Sistem" {
    linux /casper/vmlinuz boot=casper quiet splash locale=tr_TR.UTF-8
    initrd /casper/initrd
}

menuentry "$DISTRO_NAME - Güvenli Mod" {
    linux /casper/vmlinuz boot=casper xforcevesa quiet splash locale=tr_TR.UTF-8
    initrd /casper/initrd
}
EOF

    echo "🔐 EFI imajı oluşturuluyor..."
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="$BUILD_DIR/image/boot/grub/efi.img" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=$BUILD_DIR/image/boot/grub/grub.cfg"
    
    echo "💿 ISO imajı oluşturuluyor..."
    cd "$BUILD_DIR/image"
    
    xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -V "$DISTRO_NAME $DISTRO_VERSION" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/syslinux/mbr/isohdpfx.bin \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot -isohybrid-gpt-basdat \
        -output "$HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso" \
        .
    
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
    echo "📀 ISO dosyanız: $HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso"
    echo "👤 Kullanıcı: $LIVE_USER"
    echo "🔑 Şifre: $LIVE_PASS"
    echo ""
    echo "ISO'yu VirtualBox, VMware veya USB'ye yazarak test edebilirsiniz."
    echo "USB'ye yazmak için: sudo dd if=$HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso of=/dev/sdX bs=4M status=progress"
}

main
