# Archer Archlinux install script

Archer Archlinux install script with EFI/MBR bootloader (GRUB)
* /boot partition (400M)
* /root partition (Auto)
* swap partitoon (Auto/manual/none)

Download script `wget https://gitlab.com/mietinen/archer/-/raw/master/archer.sh`

Edit archer.sh `vim archer.sh`
```
# Some settings
hostname="archer"		# Machine hostname
username="mietinen"		# Main user
device="/dev/sda"		# Drive for install (something like /dev/nvme0n1 or /dev/sda)
useefi=false			# Use EFI boot (true/false)
locale="en_GB"			# Locale, en_GB for english with sane time and date format
keymap="no"			# Keymap (localectl list-keymaps)
timezone="Europe/Oslo"		# Timezone (located in /usr/share/zoneinfo/../..)
swapsize="3G"			# Size of swap partition (1500M, 8G, auto=MemTotal, 0=no swap)
installyay=true			# Install yay AUR helper (true/false)
				# Also installs: base-devel git go sudo

# pkglist.txt for extra packages (blank will use pkglist.txt from pwd)
pkglist="https://gitlab.com/mietinen/archer/-/raw/master/pkglist.txt"

# Dotfiles git repo (blank for none)
dotfilesrepo=""
```
Run script `sh archer.sh`
