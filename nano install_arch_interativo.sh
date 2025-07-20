#!/bin/bash
set -e

clear
echo "🚀 Instalador Arch Linux Interativo com XFCE, ZRAM, Swap e Autologin"

# --- Perguntas interativas ---
read -rp "Nome do usuário: " USUARIO
read -rp "Nome do host: " HOSTNAME
read -rp "Tamanho da swapfile (ex: 1G, 512M): " SWAPSIZE

# --- Escolher disco ---
echo "\n💽 Discos disponíveis:"
lsblk -d -n -e 7,11 -o NAME,SIZE | awk '{print " /dev/" $1 " (" $2 ")"}'
echo ""
read -rp "Digite o disco para instalar (ex: /dev/sda): " DISK

PART_BOOT="${DISK}1"
PART_ROOT="${DISK}2"

# --- Confirmação ---
echo "⚠️ Todos os dados em $DISK serão apagados!"
read -rp "Tem certeza que deseja continuar? (s/N): " CONFIRM
[[ $CONFIRM != "s" && $CONFIRM != "S" ]] && echo "❌ Cancelado." && exit 1

# --- Detectar BIOS ou UEFI ---
if [ -d /sys/firmware/efi ]; then
    echo "🧭 Sistema iniciado em modo UEFI"
    BOOT_MODE="UEFI"
else
    echo "🧭 Sistema iniciado em modo BIOS (Legacy)"
    BOOT_MODE="BIOS"
fi

# --- Particionamento ---
echo "🧹 Criando partições em $DISK..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    mkfs.fat -F32 "$PART_BOOT"
else
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary ext4 1MiB 512MiB
    parted -s "$DISK" set 1 boot on
    parted -s "$DISK" mkpart primary ext4 512MiB 100%
    mkfs.ext4 "$PART_BOOT"
fi

mkfs.ext4 "$PART_ROOT"

# --- Montagem ---
mount "$PART_ROOT" /mnt
mkdir /mnt/boot
mount "$PART_BOOT" /mnt/boot

# --- Instalação base ---
echo "📦 Instalando sistema base..."
pacstrap -K /mnt base base-devel linux linux-firmware linux-lts sudo neovim grub networkmanager git man-db man-pages nano

# --- Fstab ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- Script dentro do chroot ---
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone e Locale
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

sed -i 's/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Usuário e sudo
passwd -l root
useradd -m -G wheel,audio,video,optical,storage,power $USUARIO
passwd -d $USUARIO
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers

# Interface gráfica e som
pacman -Sy --noconfirm \
  xorg xorg-xinit xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
  intel-ucode xf86-video-intel mesa \
  pulseaudio pulseaudio-alsa alsa-utils \
  pipewire pipewire-pulse wireplumber zram-generator \
  vlc firefox file-roller unzip p7zip unrar tar xz zip zstd ntfs-3g exfatprogs usbutils dosfstools gvfs gvfs-mtp

systemctl enable NetworkManager
systemctl enable lightdm

# GRUB
if [ "$BOOT_MODE" = "UEFI" ]; then
    pacman -Sy --noconfirm efibootmgr
    mkdir -p /boot/EFI
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc $DISK
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Swapfile
fallocate -l $SWAPSIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# ZRAM
cat > /etc/systemd/zram-generator.conf <<ZZZ
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZZZ

systemctl daemon-reexec

# Autologin terminal + XFCE
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USUARIO --noclear %I \$TERM
AUTOLOGIN

echo "exec startxfce4" > /home/$USUARIO/.xinitrc
chown $USUARIO:$USUARIO /home/$USUARIO/.xinitrc

# Neovim e plugins
pacman -Sy --noconfirm neovim python python-pip nodejs npm git
sudo -u $USUARIO pip install --user black isort
sudo -u $USUARIO mkdir -p /home/$USUARIO/.config/nvim/lua

cat > /home/$USUARIO/.config/nvim/init.lua <<NVIMINIT
vim.o.number = true
vim.o.relativenumber = true
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true

require('plugins')
NVIMINIT

cat > /home/$USUARIO/.config/nvim/lua/plugins.lua <<NVIMPLUG
return require('packer').startup(function()
    use 'wbthomason/packer.nvim'
    use 'neovim/nvim-lspconfig'
    use 'hrsh7th/nvim-cmp'
    use 'hrsh7th/cmp-nvim-lsp'
    use 'nvim-treesitter/nvim-treesitter'
    use 'nvim-lua/plenary.nvim'
    use 'nvim-telescope/telescope.nvim'
end)
NVIMPLUG

sudo -u $USUARIO git clone --depth 1 https://github.com/wbthomason/packer.nvim \
    /home/$USUARIO/.local/share/nvim/site/pack/packer/start/packer.nvim

# Temas e aparência estilo Kali Linux
pacman -Sy --noconfirm lxappearance
sudo -u $USUARIO mkdir -p /home/$USUARIO/.themes /home/$USUARIO/.icons /home/$USUARIO/Imagens
cd /home/$USUARIO/Downloads

# Baixar temas estilo Kali (GTK e ícones)
sudo -u $USUARIO git clone https://gitlab.com/kalilinux/packages/kali-themes.git
cp -r kali-themes/share/themes/* /usr/share/themes/
cp -r kali-themes/share/icons/* /usr/share/icons/

# Baixar wallpaper do Kali
sudo -u $USUARIO wget -O /home/$USUARIO/Imagens/kali-wallpaper.jpg https://www.kali.org/images/kali-2023/kali-dragon-2023.jpg

# Aplicar como plano de fundo padrão no XFCE
sudo -u $USUARIO xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s /home/$USUARIO/Imagens/kali-wallpaper.jpg || true

EOF

echo "\n🎉 Instalação finalizada com sucesso! Remova o pendrive e reinicie."
