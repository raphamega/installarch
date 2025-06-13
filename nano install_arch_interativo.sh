#!/bin/bash
set -e

echo "🚀 Instalador Arch Linux Completo (BIOS + XFCE + ZRAM + Swap + Autologin direto no XFCE)"

# --- Configurações interativas ---
read -rp "Nome do usuário: " USUARIO
read -rp "Nome do host: " HOSTNAME
read -rp "Tamanho da swapfile (ex: 1G, 512M): " SWAPSIZE

DISK="/dev/sda"
PART_BOOT="${DISK}1"
PART_ROOT="${DISK}2"

echo "⚠️ ATENÇÃO: todo conteúdo em $DISK será apagado!"
read -rp "Continuar? (s/N): " CONFIRM
[[ $CONFIRM != "s" && $CONFIRM != "S" ]] && echo "Cancelado." && exit 1

# --- Particionamento ---
echo "🧹 Criando partições em $DISK..."
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 512MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart primary ext4 512MiB 100%

mkfs.ext4 "$PART_BOOT"
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

# --- Configuração dentro do chroot ---
echo "🔧 Configurando sistema dentro do chroot..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone e locale
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

# Root sem senha (bloqueado)
passwd -l root

# Usuário sem senha
useradd -m -G wheel,audio,video,optical,storage,power $USUARIO
passwd -d $USUARIO

# sudoers: permitir grupo wheel
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers

# Pacotes extras para GUI e som
pacman -Sy --noconfirm \
  xorg xorg-xinit xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
  intel-ucode xf86-video-intel mesa \
  pulseaudio pulseaudio-alsa alsa-utils \
  pipewire pipewire-pulse wireplumber zram-generator \
  vlc firefox file-roller unzip p7zip unrar tar xz zip zstd ntfs-3g exfatprogs usbutils dosfstools gvfs gvfs-mtp

# Habilitar serviços
systemctl enable NetworkManager
systemctl enable lightdm

# Grub
grub-install --target=i386-pc $DISK
grub-mkconfig -o /boot/grub/grub.cfg

# Swapfile
fallocate -l $SWAPSIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# ZRAM config
cat > /etc/systemd/zram-generator.conf <<ZZZ
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZZZ

systemctl daemon-reexec

# Autologin no tty1 para o usuário
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USUARIO --noclear %I \$TERM
AUTOLOGIN

# Configurar startxfce4 no xinitrc
echo "exec startxfce4" > /home/$USUARIO/.xinitrc
chown $USUARIO:$USUARIO /home/$USUARIO/.xinitrc

# Instalar neovim, python, nodejs e plugins
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

sudo -u $USUARIO mkdir -p /home/$USUARIO/.local/share/nvim/site/pack/packer/start
sudo -u $USUARIO git clone --depth 1 https://github.com/wbthomason/packer.nvim /home/$USUARIO/.local/share/nvim/site/pack/packer/start/packer.nvim

EOF

echo "🎉 Instalação completa! Remova o pendrive e reinicie o sistema."
