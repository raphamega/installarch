#!/bin/bash

set -e

### CONFIGURAÇÕES INICIAIS ###
USER="rcm"
PASSWORD="123456"
HOSTNAME="arch-pc"

### DISCO A SER INSTALADO ###
DISK="/dev/sda"

### PARTICIONAMENTO AUTOMÁTICO BIOS ###
echo "Particionando $DISK..."
parted -s $DISK mklabel msdos
parted -s $DISK mkpart primary ext4 1MiB 1GiB
parted -s $DISK set 1 boot on
parted -s $DISK mkpart primary ext4 1GiB 100%

mkfs.ext4 ${DISK}1
mkfs.ext4 ${DISK}2

mount ${DISK}2 /mnt
mkdir /mnt/boot
mount ${DISK}1 /mnt/boot

### CONFIGURAÇÃO DE PACOTES BASE ###
pacstrap -K /mnt base linux-lts linux-firmware sudo neovim grub networkmanager git man-db man-pages base-devel

### FSTAB ###
genfstab -U /mnt >> /mnt/etc/fstab

### CHROOT PARA CONFIGURAÇÕES DO SISTEMA ###
arch-chroot /mnt /bin/bash <<EOF

# Locale
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc
echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
export LANG=pt_BR.UTF-8

# Hostname
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Root password
echo root:$PASSWORD | chpasswd

# Usuário comum
useradd -m -G wheel,audio,video,optical,storage $USER
echo $USER:$PASSWORD | chpasswd
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers

# Bootloader (BIOS)
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# NetworkManager
systemctl enable NetworkManager

# ZRAM
cat <<ZZZ > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
ZZZ

# Autologin para terminal (getty)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat <<AUTOLOGIN > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
AUTOLOGIN

# XFCE e pacotes gráficos
pacman -Sy --noconfirm xorg xorg-xinit xfce4 xfce4-goodies gvfs gvfs-mtp xf86-video-intel

# Suporte a áudio (sem pipewire)
pacman -Sy --noconfirm pulseaudio pulseaudio-alsa alsa-utils

# Suporte a arquivos e mídia
pacman -Sy --noconfirm vlc firefox file-roller unzip p7zip unrar tar xz zip zstd ntfs-3g exfatprogs usbutils dosfstools

# Ambiente do usuário padrão
echo "exec startxfce4" > /home/$USER/.xinitrc
chown $USER:$USER /home/$USER/.xinitrc

# Neovim IDE para Python/Django
pacman -Sy --noconfirm neovim python python-pip nodejs npm
sudo -u $USER pip install black isort
sudo -u $USER mkdir -p /home/$USER/.config/nvim

cat <<NVIM > /home/$USER/.config/nvim/init.lua
vim.o.number = true
vim.o.relativenumber = true
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true

require('plugins')
NVIM

cat <<PLUG > /home/$USER/.config/nvim/lua/plugins.lua
return require('packer').startup(function()
    use 'wbthomason/packer.nvim'
    use 'neovim/nvim-lspconfig'
    use 'hrsh7th/nvim-cmp'
    use 'hrsh7th/cmp-nvim-lsp'
    use 'nvim-treesitter/nvim-treesitter'
    use 'nvim-lua/plenary.nvim'
    use 'nvim-telescope/telescope.nvim'
end)
PLUG

sudo -u $USER mkdir -p /home/$USER/.local/share/nvim/site/pack/packer/start
sudo -u $USER git clone --depth 1 https://github.com/wbthomason/packer.nvim /home/$USER/.local/share/nvim/site/pack/packer/start/packer.nvim

EOF

### FINAL ###
echo "Instalação finalizada. Pode rebootar. Lembre-se de remover o ISO."
