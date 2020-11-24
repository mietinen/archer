# Archer - Archlinux install script

Archer Archlinux install script with EFI/MBR bootloader (GRUB)

* /boot partition (400M)
	* EFI/legacy support
* root btrfs partition (Auto)
	* @root, @home, @srv, @vcache, @vlog, @vtmp, @snapshots, @swap subvolumes
	* dm-crypt/LUKS support
* swap file (Auto/manual/none)

Download script `curl -L https://git.io/JkPC9 -o archer.sh`

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
swapsize="auto"		# Size of swap file in MB (auto=MemTotal, 0=no swap)
encrypt=true		# Set up dm-crypt/LUKS on root and swap partition
multilib=false		# Enable multilib (true/false)
aurhelper="paru"	# Install AUR helper (yay,paru.. blank for none)
			# Also installs: base-devel git

# pkglist.txt for extra packages (blank will use pkglist.txt from local directory)
pkglist="https://raw.githubusercontent.com/mietinen/archer/master/pkglist.txt"

# Dotfiles git repo (blank for none)
dotfilesrepo="https://github.com/mietinen/shell.git"
```

Run script `bash archer.sh`

## pktlist.txt

You can make you're own pkglist.txt using `pacman -Qqe > pkglist.txt`  
The script first installs what it finds in official repositories, then tries what's rest from the AUR repositories. Installing AUR packages depends on `aurhelper`  
Lines starting with an - is removed at the end, if there are no dependencies. Making it posible to install package groups and removing what you dont want. `-xfce4-terminal`

## Dotfiles

Feel free to use my dotfiles, but it doesn't contain much useful stuff.
