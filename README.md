# Archer - Archlinux install script

Archer Archlinux install script with EFI/MBR bootloader (GRUB)

* /boot partition (400M)
* /root partition (Auto)
* swap partitoon (Auto/manual/none)

Download script `wget https://gitlab.com/mietinen/archer/-/raw/master/archer.sh`

Edit archer.sh `vim archer.sh`

```
# Some settings
hostname="archer"	# Machine hostname
username="mietinen"	# Main user
device="/dev/nvme0n1"	# Drive for install (something like /dev/nvme0n1 or /dev/sda)
useefi=true		# Use EFI boot (true/false)
language="en_GB"	# Language for locale.conf (en_GB for english with sane time format)
locale="nb_NO"		# Numbers, messurement, etc. for locale.conf (safe to use same as language)
keymap="no"		# Keymap (localectl list-keymaps)
timezone="Europe/Oslo"	# Timezone (located in /usr/share/zoneinfo/../..)
swapsize="auto"		# Size of swap partition (1500M, 8G, auto=MemTotal, 0=no swap)
installyay=true		# Install yay AUR helper (true/false)
			# Also installs: base-devel git go sudo

# pkglist.txt for extra packages (blank will use pkglist.txt from pwd)
pkglist="https://gitlab.com/mietinen/archer/-/raw/master/pkglist.txt"

# Dotfiles git repo (blank for none)
dotfilesrepo=""
```

Run script `bash archer.sh`

## pktlist.txt

You can make you're own pkglist.txt using `pacman -Qqe > pkglist.txt`  
The script first installs what it finds in official repositories, then tries what's rest from the AUR repositories. Installing AUR packages depends on `yayinstall=true`  
Lines starting with an - is removed at the end, if there are no dependencies. Making it posible to install package groups and removing what you dont want. `-xfce4-terminal`

## Dotfiles

Feel free to use my dotfiles, but it doesn't contain much useful stuff.
