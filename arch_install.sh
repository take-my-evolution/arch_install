#!/bin/bash

BASEDIR=$(dirname $(realpath "$0"))
cpu_type=""
gpu_type=""
wm_type=""

# Значения переменных по умолчанию
default_diskname="sda"
default_root_password="rootpass"
default_username="user"
default_user_password="userpass"
default_hostname="archlinux"
default_cpu_type="intel"
default_gpu_type="nvidia"
default_wm_type="i3wm"

# Пользовательский ввод
echo "Do you want to use default values? (y/n)"
read use_defaults

if [ "$use_defaults" == "y" ]; then
  diskname=$default_diskname
  root_password=$default_root_password
  username=$default_username
  user_password=$default_user_password
  hostname=$default_hostname
  cpu_type=$default_cpu_type
  gpu_type=$default_gpu_type
  wm_type=$default_wm_type
else
  echo -n "Enter disk name: "
  read diskname
  echo -n "Enter root password: "
  read root_password
  echo -n "Enter user name: "
  read username
  echo -n "Enter user password: "
  read user_password
  echo -n "Enter hostname: "
  read hostname

  # Выбор CPU
  echo "Select CPU type:"
  echo "1) Intel"
  echo "2) AMD"
  echo "3) ARM (e.g., Mac M3)"
  read cpu_choice

  case $cpu_choice in
    1) cpu_type="intel" ;;
    2) cpu_type="amd" ;;
    3) cpu_type="arm" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  # Выбор графического окружения
  echo "Select graphical environment:"
  echo "1) i3wm"
  echo "2) Hyperland"
  echo "3) No graphical environment (for server setup)"
  read wm_choice

  case $wm_choice in
    1) wm_type="i3wm";;
    2) wm_type="hyperland";;
    3) wm_type="none";;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  # Если выбран i3wm, требуется выбрать GPU
  if [ "$wm_type" == "i3wm" ]; then
    echo "Select GPU type for i3wm:"
    echo "1) NVIDIA"
    echo "2) Radeon"
    echo "3) Intel"
    read gpu_choice

    case $gpu_choice in
      1) gpu_type="nvidia" ;;
      2) gpu_type="radeon" ;;
      3) gpu_type="intel_video" ;;
      *) echo "Invalid choice"; exit 1 ;;
    esac
  elif [ "$wm_type" == "hyperland" ]; then
    gpu_type="hyperland_gpu"
  fi
fi

# Очистка mnt
umount -R /mnt
rm -rf /mnt/*

# Создание разделов
(echo o; sleep 1; echo w) | fdisk /dev/${diskname}
(echo n; echo p; echo 1; echo ''; echo +1024M; sleep 1; echo w) | fdisk /dev/${diskname}
(echo n; echo p; echo 2; echo ''; echo ''; sleep 1; echo w) | fdisk /dev/${diskname}
(echo a; echo 1; sleep 1; echo w) | fdisk /dev/${diskname}

# Форматирование дисков
mkfs.vfat -F32 /dev/${diskname}1
mkfs.btrfs -f -L 'root' /dev/${diskname}2

# Монтирование
mount /dev/${diskname}2 /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
umount /mnt
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@ /dev/${diskname}2 /mnt
mkdir -p /mnt/{home,.snapshots}
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@home /dev/${diskname}2 /mnt/home
mount -o rw,noatime,compress=lzo,space_cache=v2,discard=async,subvol=@snapshots /dev/${diskname}2 /mnt/.snapshots
mkdir -p /mnt/boot/efi
mount /dev/${diskname}1 /mnt/boot/efi

# Установка
sed -i s/'#ParallelDownloads = 5'/'ParallelDownloads = 13'/g /etc/pacman.conf
reflector --verbose -l 5 -p https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy

# Установка общих пакетов
pacstrap -i /mnt $(cat $BASEDIR/pacman_lists/pacman_list_common.txt) --noconfirm

# Установка пакетов для выбранного процессора
pacstrap -i /mnt $(cat $BASEDIR/pacman_lists/pacman_list_$cpu_type.txt) --noconfirm

# Установка драйвера GPU (если необходимо)
if [ "$gpu_type" != "none" ]; then
  pacstrap -i /mnt $(cat $BASEDIR/pacman_lists/pacman_list_$gpu_type.txt) --noconfirm
fi

# Установка пакетов для выбранного графического окружения
if [ "$wm_type" != "none" ]; then
  pacstrap -i /mnt $(cat $BASEDIR/pacman_lists/pacman_list_$wm_type.txt) --noconfirm
fi

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Добавление пользователя и установка паролей
arch-chroot /mnt /bin/bash -c "echo 'root:$root_password' | chpasswd"
arch-chroot /mnt /bin/bash -c "useradd -m -G wheel -s /bin/bash $username"
arch-chroot /mnt /bin/bash -c "echo '$username:$user_password' | chpasswd"

# Настройка sudo и других параметров
arch-chroot /mnt /bin/bash -c "sed -i s/'# %wheel ALL=(ALL:ALL) ALL'/'%wheel ALL=(ALL:ALL) ALL'/g /etc/sudoers"
arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman'>>/etc/sudoers"

# Настройка локалей и временной зоны
arch-chroot /mnt /bin/bash -c "sed -i s/'#en_US.UTF-8'/'en_US.UTF-8'/g /etc/locale.gen"
arch-chroot /mnt /bin/bash -c "locale-gen"
arch-chroot /mnt /bin/bash -c "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
arch-chroot /mnt /bin/bash -c "echo 'KEYMAP=ru' > /etc/vconsole.conf"
arch-chroot /mnt /bin/bash -c "echo 'FONT=cyr-sun16' >> /etc/vconsole.conf"
arch-chroot /mnt /bin/bash -c "echo '$hostname' > /etc/hostname"

# Настройка времени
arch-chroot /mnt /bin/bash -c "ln -fs /usr/share/zoneinfo/Europe/Moscow /etc/localtime"
arch-chroot /mnt /bin/bash -c "hwclock --systohc"

# Установка и настройка GRUB
arch-chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='Arch'"
arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

# Включение NetworkManager
arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"
