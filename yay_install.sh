#!/bin/bash

sudo -u username mkdir /home/username/yay&&
cd /home/username/yay&&
sudo -u username curl -OJ 'https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=yay'&&
sudo -u username makepkg -si --noconfirm&&
yay --version
