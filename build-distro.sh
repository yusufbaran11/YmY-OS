#!/bin/bash

# Kolay Linux Dağıtımı Oluşturucu (Nihai Düzeltilmiş Versiyon)
# Ubuntu tabanlı özelleştirilmiş bir dağıtım yapılandırması

set -e

DISTRO_NAME="YmY-OS"
DISTRO_VERSION="1.0"
BUILD_DIR="$HOME/distro-build"

# İstenen Kullanıcı ve Şifre
LIVE_USER="live"
# ! karakterinin kabuk içinde sorun yaratmaması için güvenli kullanıma dikkat edilmeli.
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
        grub-common # Grub araçlarının tam olarak kurulduğundan emin olmak için
}

# Temel sistem oluştur
create_base_system() {
    echo "🔧 Temel sistem oluşturuluyor..."
    
    # Önceki build klasörünü temizle
    if [ -d "$BUILD_DIR" ]; then
        echo "Eski build klasörü temizleniyor..."
        sudo rm -rf "$BUILD_DIR"
    fi
    
    # Gerekli dizinleri oluştur
    mkdir -p "$BUILD_DIR"/{chroot,image/{casper,isolinux,install,boot/grub}}
    
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
                http://tr.archive.ubuntu.com/ubuntu/ || {
                    echo "❌ İkinci deneme de başarısız oldu. Çıkılıyor."
                    exit 1
                }
        }
    
    echo "$DISTRO_NAME" | sudo tee "$BUILD_DIR/chroot/etc/hostname"
}

# Chroot ortamına gir ve yapılandır
configure_system() {
    echo "⚙️  Sistem yapılandırılıyor..."
    
    # DNS ayarları
    sudo cp /etc/resolv.conf "$BUILD_DIR/chroot/etc/resolv.conf"
    
    # Chroot içinde çalışacak script
    cat > /tmp/chroot_config.sh << CHROOT_EOF
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
# Temel ve Live sistem paketleri (grub-efi-amd64 eklendi)
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
    grub2-common \
    grub-efi-amd64

# KRİTİK DÜZELTME: Kernel dosyalarının varlığını garanti etmek için initrd oluşturulur.
# Bu, "Kernel veya Initrd dosyası bulunamadı" hatasını çözer.
update-initramfs -u

# Masaüstü ortamı - GNOME
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

# ... (Diğer paket ve kullanıcı yapılandırmaları aynı) ...

# Kullanıcı oluştur ve şifre ata (Değişkenler kabuk tarafından genişletilecek)
useradd -m -s /bin/bash $LIVE_USER
echo "$LIVE_USER:$LIVE_PASS" | chpasswd
usermod -aG sudo $LIVE_USER

# ... (Hoşgeldin mesajı ve GDM ayarları aynı) ...

# Gerekli dosya sistemi temizliği ve temp dosyaların silinmesi
apt-get clean
# /var/lib/apt/lists/* temizliği
rm -rf /tmp/* ~/.bash_history /var/lib/apt/lists/*
# Log dosyalarını temizle
find /var/log -type f -delete
CHROOT_EOF

    # Script'i chroot'a kopyala ve çalıştır
    sudo cp /tmp/chroot_config.sh "$BUILD_DIR/chroot/tmp/"
    sudo chmod +x "$BUILD_DIR/chroot/tmp/chroot_config.sh"
    # Mount point'leri chroot'a bağla
    sudo mount --bind /dev "$BUILD_DIR/chroot/dev"
    sudo mount --bind /sys "$BUILD_DIR/chroot/sys"
    sudo mount --bind /proc "$BUILD_DIR/chroot/proc"
    
    # Chroot içinde scripti çalıştır
    sudo chroot "$BUILD_DIR/chroot" /tmp/chroot_config.sh
    
    # Hatalı EFI Kopyalama Adımı Kaldırıldı!
    # Bunun yerine grub-mkstandalone ile efi.img oluşturulacak.

    # UEFI imajı oluşturma: Hem EFI hem de BIOS desteği için gerekli.
    # Bu adımı chroot dışında yapıyoruz.
    # Bu adım, "GRUB EFI boot klasörü kopyalanamadı" uyarısını çözmelidir.
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="$BUILD_DIR/image/boot/grub/efi.img" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=$BUILD_DIR/image/boot/grub/grub.cfg"
    
    # Mount point'leri temizle
    sudo umount "$BUILD_DIR/chroot/dev"
    sudo umount "$BUILD_DIR/chroot/sys"
    sudo umount "$BUILD_DIR/chroot/proc"
}

# ISO imajını oluştur
create_iso() {
    echo "💿 ISO imajı oluşturuluyor..."
    
    # Kernel ve initrd'nin tam isimlerini bul ve kopyala
    # Düzeltme sonrası, bu komutlar artık dosyaları bulmalıdır.
    VMLINUZ_FILE=$(sudo find "$BUILD_DIR/chroot/boot/" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n 1)
    INITRD_FILE=$(sudo find "$BUILD_DIR/chroot/boot/" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n 1)
    
    if [ -z "$VMLINUZ_FILE" ] || [ -z "$INITRD_FILE" ]; then
        echo "❌ KRİTİK HATA: Kernel (VMLINUZ) veya Initrd dosyası hala bulunamadı."
        echo "Lütfen 'linux-generic' paketinin chroot içinde doğru kurulduğundan ve 'update-initramfs -u' komutunun çalıştığından emin olun."
        exit 1
    fi
    
    echo "Kernel kopyalanıyor: $VMLINUZ_FILE -> $BUILD_DIR/image/casper/vmlinuz"
    sudo cp "$VMLINUZ_FILE" "$BUILD_DIR/image/casper/vmlinuz"
    echo "Initrd kopyalanıyor: $INITRD_FILE -> $BUILD_DIR/image/casper/initrd"
    sudo cp "$INITRD_FILE" "$BUILD_DIR/image/casper/initrd"
    
    # Manifest oluştur
    sudo chroot "$BUILD_DIR/chroot" dpkg-query -W --showformat='${Package} ${Version}\n' | \
        sudo tee "$BUILD_DIR/image/casper/filesystem.manifest"
    
    # SquashFS oluştur
    echo "📦 Dosya sistemi sıkıştırılıyor (bu biraz zaman alabilir)..."
    # Hariç tutulan dizinler düzeltildi.
    sudo mksquashfs "$BUILD_DIR/chroot" "$BUILD_DIR/image/casper/filesystem.squashfs" \
        -comp xz -b 1M \
        -e boot \
        -e dev \
        -e proc \
        -e sys

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
    
    # Bootloader dosyaları
    sudo cp /usr/lib/syslinux/modules/bios/isolinux.bin "$BUILD_DIR/image/isolinux/"
    sudo cp /usr/lib/syslinux/modules/bios/vesamenu.c32 "$BUILD_DIR/image/isolinux/"
    
    # isolinux.cfg
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

    # GRUB yapılandırması (EFI ve PC)
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
    
    # ISO oluşturma komutu
    echo "💿 xorriso ile hibrit ISO imajı oluşturuluyor..."
    cd "$BUILD_DIR/image"
    
    xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-read-filenames \
        -V "$DISTRO_NAME $DISTRO_VERSION" \
        -publisher "YmY Distro Team" \
        -preparer "YmY Build Script" \
        -appid "YmY-OS Live" \
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
    echo "ISO dosyanız: $HOME/${DISTRO_NAME}-${DISTRO_VERSION}.iso"
    echo "Varsayılan kullanıcı: $LIVE_USER"
    echo "Varsayılan şifre: $LIVE_PASS"
    echo ""
    echo "Bu ISO'yu VirtualBox veya VMware'de test edebilirsiniz."
}

main
