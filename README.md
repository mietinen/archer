# Archer - Archlinux install script

Archer Archlinux install script with EFI/MBR bootloader (GRUB)

* /boot/efi partition (200M)
    * EFI/legacy support
* root btrfs partition
    * @root, @home, @srv, @var, @swap subvolumes
    * DBpath moved to /usr/lib/pacman for snapshot
    * dm-crypt/LUKS support
* swap file (Auto/manual/none)

## Usage
**To use this for yourself, clone this repository and change packages, dotfiles and what ever to fit your needs.**

Or simply just download, edit some settings and run:
```sh
curl -L https://git.io/JkPC9 -o archer.sh
vim archer.sh
bash archer.sh
```

## pktlist.txt

You can make you're own pkglist.txt using the makepkglist.sh script `bash makepkglist.sh > pkglist.txt`  
or simply `pacman -Qqe > pkglist.txt`

The script first installs what it finds in official repositories, then tries what's left from the AUR repositories. Installing AUR packages depends on `aurhelper`  

## Dotfiles

Feel free to use my dotfiles, but it doesn't contain much useful stuff.
