#!/bin/bash
set -e

echo "🔧 Script de instalação do Arch Linux (modo BIOS + XFCE + ZRAM + Swap)"

# === CONFIGURAÇÕES INTERATIVAS ===
read -p "➡️  Nome do usuário: " USUARIO
read -p "➡️  Nome do host (hostname): " HOSTNAME
read -p "➡️  Tamanho da swapfile (ex: 1G, 512M): " SWAPSIZE

DISCO="/dev/sda"
PART_BOOT="${DISCO}1"
PART_ROOT="${DISCO}2"

echo "⚠️  Isso irá apagar TODO o conteúdo do disco ${DISCO}!"
read -p "❓ Deseja continuar? (s/N): " CONFIRM
[[ "$CONFIRM" != "s" ]] && echo "❌ Cancelado." && exit 1

# === PARTICIONAMENTO ===
echo "🧹 Limpando e particionando o disco..."
parted -s "$DISCO" mklabel msdos
parted -s "$DISCO" mkpart primary ext4 1MiB 512MiB
parted -s "$DISCO" mkpart primary ext4 512MiB 100%

mkfs.ext4 "$PART_BOOT"
mkfs.ext4 "$PART_ROOT"

# === MONTAGEM ===
mount "$PART_ROOT" /mnt
mkdir /mnt/boot
mount "$PART_BOOT" /mnt/boot

# === INSTALAR BASE ===
pacstrap -K /mnt base base-devel linux linux-firmware nano

# === FSTAB ===
genfstab -U /mnt >> /mnt/etc/fstab

# === SCRIPT PÓS-INSTALAÇÃO ===
cat <<EOF > /mnt/root/pos_instalacao.sh
#!/bin/bash
set -e

ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

sed -i 's/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=pt_BR.UTF-8' > /etc/locale.conf
echo 'KEYMAP=br-abnt2' > /etc/vconsole.conf

echo '$HOSTNAME' > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo "🔐 Defina a senha do root:"
passwd

pacman -Sy --noconfirm grub networkmanager intel-ucode \
    xf86-video-nouveau mesa \
    xorg xorg-xinit \
    xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
    pipewire pipewire-pulse wireplumber \
    zram-generator sudo

systemctl enable NetworkManager
systemctl enable lightdm

grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

fallocate -l $SWAPSIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

cat <<ZR > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZR

systemctl daemon-reexec
systemctl start /dev/zram0

useradd -m -G wheel $USUARIO
echo "🔐 Defina a senha para o usuário $USUARIO:"
passwd $USUARIO

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "✅ Instalação dentro do sistema concluída. Pode reiniciar!"
EOF

chmod +x /mnt/root/pos_instalacao.sh

# === ENTRA NO CHROOT ===
arch-chroot /mnt /root/pos_instalacao.sh

echo "🟢 Instalação concluída com sucesso. Remova o pendrive e reinicie!"
