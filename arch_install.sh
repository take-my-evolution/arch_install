#!/bin/bash
BASEDIR=$(dirname $(realpath "$0"))
pacman_list=$(cat pacman_list.txt)
binmod="setfont"

echo -n "Enter disk name"
read diskname
echo -n "Enter root password: "
read root_password
echo -n "Enter user name: "
read username
echo -n "Enter user password: "
read user_password
echo -n "Enter hostname "
read hostname

#очитска mnt
umount -R /mnt
rm -rf /mnt/*
#Создание разделов ${diskname}umount -l /mnt
(echo o; sleep 1; echo  w) | fdisk /dev/${diskname}
(echo n; echo p; echo 1; echo ''; echo +1024M; sleep 1; echo w) | fdisk /dev/${diskname}
(echo n; echo p; echo 2; echo ''; echo ''; sleep 1; echo w) | fdisk /dev/${diskname}
(echo a; echo  1; sleep 1; echo w) | fdisk /dev/${diskname}
#Форматирование дисков'
mkfs.vfat -F32 /dev/${diskname}1
mkfs.btrfs -f -L 'root' /dev/${diskname}2

#Монтирование btrfs,boot
mount /dev/${diskname}2 /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
umount /mnt
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@ /dev/${diskname}2 /mnt
mkdir -p /mnt/{home,.snapshots}
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@home /dev/${diskname}2 /mnt/home
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,subvol=@snapshots  /dev/${diskname}2 /mnt/.snapshots
mkdir -p /mnt/boot/efi
mount /dev/${diskname}1 /mnt/boot/efi

# Установка 
sed -i s/'#ParallelDownloads = 5'/'ParallelDownloads = 13'/g /etc/pacman.conf
reflector --verbose -l 5 -p https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy
pacstrap -i /mnt base base-devel  linux  linux-firmware reflector intel-ucode --noconfirm 
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -c "echo 'export username=$username' >> /etc/bash.bashrc"

arch-chroot /mnt /bin/bash -c "sed -i s/'# %wheel ALL=(ALL:ALL) ALL'/'%wheel ALL=(ALL:ALL) ALL'/g /etc/sudoers"
arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman'>>/etc/sudoers"
arch-chroot /mnt /bin/bash -c "echo 'deny = 10' >>/etc/security/faillock.conf"
arch-chroot /mnt /bin/bash -c "echo 'unlock_time = 60' >>/etc/security/faillock.conf"



arch-chroot /mnt /bin/bash -c "sed -i s/'#Color'/'Color'/g /etc/pacman.conf"
arch-chroot /mnt /bin/bash -c "sed -i s/'#en_US.UTF-8'/'en_US.UTF-8'/g /etc/locale.gen"
arch-chroot /mnt /bin/bash -c "sed -i s/'#ru_RU.UTF-8'/'ru_RU.UTF-8'/g /etc/locale.gen"
arch-chroot /mnt /bin/bash -c "sed -i s/'#ParallelDownloads = 5'/'ParallelDownloads = 13'/g /etc/pacman.conf"
arch-chroot /mnt /bin/bash -c "sed -i '/^BINARIES=/ s/)/ $binmod)/' /etc/mkinitcpio.conf"

arch-chroot /mnt /bin/bash -c "locale-gen"
arch-chroot /mnt /bin/bash -c "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
arch-chroot /mnt /bin/bash -c "echo 'KEYMAP=ru' > /etc/vconsole.conf"
arch-chroot /mnt /bin/bash -c "echo 'FONT=cyr-sun16' >> /etc/vconsole.conf"

arch-chroot /mnt /bin/bash -c "echo '$hostname' > /etc/hostname"
arch-chroot /mnt /bin/bash -c "echo '127.0.0.1 localhost' > /etc/hosts"
arch-chroot /mnt /bin/bash -c "echo '::1       localhost' >> /etc/hosts"
arch-chroot /mnt /bin/bash -c "echo '127.0.0.1 $hostname.localdomain $hostname' >> /etc/hosts"

arch-chroot /mnt /bin/bash -c "ln -fs /usr/share/zoneinfo/Europe/Moscow /etc/localtime"
arch-chroot /mnt /bin/bash -c "timedatectl set-ntp true" 
arch-chroot /mnt /bin/bash -c "hwclock --systohc"

arch-chroot /mnt /bin/bash -c "reflector --verbose -l 5 -p https --sort rate --save /etc/pacman.d/mirrorlist"

arch-chroot /mnt /bin/bash -c "mkinitcpio -p linux"
arch-chroot /mnt /bin/bash -c "pacman-key --init pacman-key --populate archlinux"
arch-chroot /mnt /bin/bash -c "pacman -Syu"
arch-chroot /mnt /bin/bash -c "pacman -S $pacman_list --noconfirm"

arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"
arch-chroot /mnt /bin/bash -c "systemctl enable sshd.service"
arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='Arch'"
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

arch-chroot /mnt /bin/bash -c "echo 'root:$root_password' | chpasswd" 
arch-chroot /mnt /bin/bash -c "useradd -m -G wheel -s /bin/bash $username"
arch-chroot /mnt /bin/bash -c "echo '$username:$user_password' | chpasswd" 

export username=$username
mkdir "/mnt/home/$username/sh/"
cp "$BASEDIR/yay_install.sh" "/mnt/home/$username/sh/yay_install.sh" 
arch-chroot /mnt /bin/bash -c "chmod -R +x '/home/$username/sh'"

#instal yay
arch-chroot /mnt /bin/bash -c "sh /home/$username/sh/yay_install.sh"
sed -i s/'export username=$username'/''/g /mnt/etc/bash.bashrc
sed -i '$d' /mnt/etc/sudoers 
rm -rf /mnt/home/$username/sh
rm -rf /mnt/home/$username/yay

#create snapshot
arch-chroot /mnt /bin/bash -c "sudo btrfs subvolume snapshot / /.snapshots/start"

#install grub-btrfs

arch-chroot /mnt /bin/bash -c "pacman -S grub-btrfs inotify-tools --noconfirm"
arch-chroot /mnt /bin/bash -c "sudo systemctl start grub-btrfsd"
arch-chroot /mnt /bin/bash -c "sudo systemctl enable grub-btrfsd"
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

#i3wm