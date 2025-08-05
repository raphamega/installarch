#!/bin/bash
set -e

echo "====== INSTALADOR AUTOMÁTICO ARCH LINUX ======"

# === ETAPA 1: INFORMAÇÕES DO USUÁRIO ===
read -p "Nome do PC (hostname): " HOSTNAME
read -p "Nome do usuário: " USERNAME
read -s -p "Senha do usuário: " USERPASS
echo
read -s -p "Senha do root: " ROOTPASS
echo

# === ETAPA 2: TAMANHO DE ZRAM E SWAP ===
read -p "Quanto de RAM quer usar na ZRAM? (ex: 1G, 1500M): " ZRAM_SIZE
read -p "Deseja criar uma partição swap? Digite o tamanho (ex: 2G) ou deixe vazio para não criar: " SWAP_SIZE

# === ETAPA 3: ESCOLHA DA INTERFACE GRÁFICA ===
echo "Escolha sua interface gráfica:"
echo "1 - XFCE (leve e completa)"
echo "2 - Openbox (ultraleve)"
echo "3 - Nenhuma (modo texto)"
read -p "Opção [1/2/3]: " GUI_OPTION

# === ETAPA 4: DETECÇÃO DO MODO DE BOOT ===
if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
    echo "[+] Modo UEFI detectado"
else
    BOOT_MODE="BIOS"
    echo "[+] Modo BIOS detectado"
fi

# === ETAPA 5: ESCOLHA DO DISCO ===
lsblk
read -p "Informe o disco de destino (ex: /dev/sda): " DISK

# === ETAPA 6: PARTICIONAMENTO AUTOMÁTICO ===
wipefs -a "$DISK"
sgdisk -Z "$DISK"

if [ "$BOOT_MODE" = "UEFI" ]; then
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
else
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary ext4 1MiB 100%
    parted -s "$DISK" set 1 boot on
    ROOT_PART="${DISK}1"
fi

# === ETAPA 7: FORMATAÇÃO E MONTAGEM ===
mkfs.ext4 "$ROOT_PART"
mount "$ROOT_PART" /mnt

if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "$EFI_PART"
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
fi

# === ETAPA 8: INSTALAÇÃO DO SISTEMA BASE ===
echo "[+] Instalando base do sistema..."
pacstrap /mnt base linux linux-firmware vim sudo networkmanager zram-generator \
    unzip zip p7zip tar xz gzip bzip2 lz4 zstd --noconfirm

# === ETAPA 9: FSTAB ===
genfstab -U /mnt >> /mnt/etc/fstab

# === ETAPA 10: CONFIGURAÇÕES DENTRO DO SISTEMA ===
arch-chroot /mnt /bin/bash <<EOF

# Hostname, localtime e idioma
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

# Locale
sed -i 's/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Usuário e permissões
echo "root:$ROOTPASS" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Login automático no tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<AUL
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USERNAME --noclear %I \$TERM
AUL

# ZRAM personalizada
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram.conf <<ZRAM
[zram0]
zram-size = $ZRAM_SIZE
compression-algorithm = zstd
ZRAM

# Ativar serviços essenciais
systemctl enable NetworkManager

# Instalar bootloader
pacman -S grub efibootmgr --noconfirm
if [ "$BOOT_MODE" = "UEFI" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# === ETAPA 11: CRIAR SWAP SE DESEJADO ===
if [[ -n "$SWAP_SIZE" ]]; then
    echo "[+] Criando partição SWAP de $SWAP_SIZE..."
    parted -s "$DISK" mkpart primary linux-swap -$SWAP_SIZE 100%
    SWAP_PART="${DISK}3"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"
    echo "UUID=$(blkid -s UUID -o value $SWAP_PART) none swap sw 0 0" >> /mnt/etc/fstab
fi

# === ETAPA 12: INSTALAÇÃO DA INTERFACE GRÁFICA (SE ESCOLHIDA) ===
if [[ "$GUI_OPTION" == "1" ]]; then
    echo "[+] Instalando XFCE..."
    arch-chroot /mnt /bin/bash -c "pacman -S xfce4 xfce4-goodies xorg --noconfirm"
elif [[ "$GUI_OPTION" == "2" ]]; then
    echo "[+] Instalando Openbox..."
    arch-chroot /mnt /bin/bash -c "pacman -S openbox xorg xterm obconf tint2 --noconfirm"
fi

# === FINAL ===
echo "✅ Instalação concluída com sucesso!"
echo "Reinicie com: reboot"
