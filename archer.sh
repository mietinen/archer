#!/usr/bin/env bash

# Archer Archlinux install script
# Setup with EFI/MBR bootloader (GRUB) at 400M	/boot partition
# 						btrfs root partition
#		@root, @home, @var, @srv, @snapshots, @swap subvolumes
#						Auto/manual/none swap file
## license: LGPL-3.0 (http://opensource.org/licenses/lgpl-3.0.html)

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
installyay=true		# Install yay AUR helper (true/false)
			# Also installs: base-devel git go sudo

# pkglist.txt for extra packages (blank will use pkglist.txt from local directory)
pkglist="https://gitlab.com/mietinen/archer/-/raw/master/pkglist.txt"

# Dotfiles git repo (blank for none)
dotfilesrepo="https://gitlab.com/mietinen/shell.git"


# # # # # # # # # # # # # # # # #
#	No edit from here	#
# # # # # # # # # # # # # # # # #

if [ "${device::8}" == "/dev/nvm" ] ; then
	bootdev=${device}"p1"
	rootdev=${device}"p2"
else
	bootdev=${device}"1"
	rootdev=${device}"2"
fi
rootid=$(blkid --output export "$rootdev" | sed --silent 's/^UUID=//p')

# Set size of swap file same as total memory if set as auto
[ "$swapsize" = "auto" ] && \
	swapsize=$((($(grep MemTotal /proc/meminfo | awk '{ print $2 }')+500)/1000))

# Run at launch
aistart() {
	if [ ! "$(uname -n)" = "archiso" ]; then
		echo "This script is ment to be run from the Archlinux live medium." ; exit
	fi
	if [ "$(id -u)" -ne 0 ]; then
		 echo "This script must be run as root." ; exit
	fi

	# Setting up keyboard and clock
	# printm 'Setting up keyboard and clock'
	# loadkeys ${keymap} >/dev/null 2>>error.txt || error=true
	# timedatectl set-ntp true >/dev/null 2>>error.txt || error=true
	# showresult

	# Setting up partitions
	printm 'Setting up partitions'
	if [ "$useefi" = true ] ; then
		parted -s $device mklabel gpt >/dev/null 2>>error.txt || error=true
		sgdisk $device -n=1:0:+400M -t=1:ef00 >/dev/null 2>>error.txt || error=true
		sgdisk $device -n=2:0:0 >/dev/null 2>>error.txt || error=true
	else
		parted -s $device mklabel msdos >/dev/null 2>>error.txt || error=true
		echo -e "n\np\n\n\n+400M\na\nw" | fdisk $device >/dev/null 2>>error.txt || error=true
		echo -e "n\np\n\n\n\nw" | fdisk ${device} >/dev/null 2>>error.txt || error=true
	fi
	showresult

	# Setting up encryption
	if [ "$encrypt" = true ] ; then
		printm 'Setting up encryption'
		echo
		cryptsetup -q luksFormat --align-payload=8192 -s 256 -c aes-xts-plain64 "$rootdev" 2>>error.txt || error=true
		cryptsetup -q open "$rootdev" root 2>>error.txt || error=true
		rootdev="/dev/mapper/root"
		printm 'Encryption setup'
		showresult
	fi

	# Formating partitions
	printm 'Formating partitions'
	if [ "$useefi" = true ] ; then
		mkfs.vfat $bootdev >/dev/null 2>>error.txt || error=true
	else
		mkfs.ext4 $bootdev >/dev/null 2>>error.txt || error=true
	fi
	mkfs.btrfs -f "$rootdev" >/dev/null 2>>error.txt || error=true

	mount "$rootdev" /mnt >/dev/null 2>>error.txt || error=true
	btrfs subvolume create /mnt/@root >/dev/null 2>>error.txt || error=true
	btrfs subvolume create /mnt/@home >/dev/null 2>>error.txt || error=true
	btrfs subvolume create /mnt/@var >/dev/null 2>>error.txt || error=true
	btrfs subvolume create /mnt/@srv >/dev/null 2>>error.txt || error=true
	btrfs subvolume create /mnt/@snapshots >/dev/null 2>>error.txt || error=true
	if [ "$swapsize" != "0" ] ; then
		btrfs subvolume create /mnt/@swap >/dev/null 2>>error.txt || error=true
	fi
	umount /mnt >/dev/null 2>>error.txt || error=true
	showresult

	# Mounting partitions
	printm 'Mounting partitions'
	mount -o subvol=@root "$rootdev" /mnt >/dev/null 2>>error.txt || error=true
	mkdir -p /mnt/{boot,home,var,srv,.snapshots} >/dev/null 2>>error.txt || error=true
	mount -o subvol=@home "$rootdev" /mnt/home >/dev/null 2>>error.txt || error=true
	mount -o subvol=@var "$rootdev" /mnt/var >/dev/null 2>>error.txt || error=true
	mount -o subvol=@srv "$rootdev" /mnt/srv >/dev/null 2>>error.txt || error=true
	mount -o subvol=@snapshots "$rootdev" /mnt/.snapshots >/dev/null 2>>error.txt || error=true
	if [ "$swapsize" != "0" ] ; then
		mkdir -p /mnt/.swap >/dev/null 2>>error.txt || error=true
		mount -o subvol=@swap "$rootdev" /mnt/.swap >/dev/null 2>>error.txt || error=true
		truncate -s 0 /mnt/.swap/swapfile >/dev/null 2>>error.txt || error=true
		chattr +C /mnt/.swap/swapfile >/dev/null 2>>error.txt || error=true
		btrfs property set /mnt/.swap/swapfile compression none >/dev/null 2>>error.txt || error=true
		dd if=/dev/zero of=/mnt/.swap/swapfile bs=1M count="$swapsize" >/dev/null 2>>error.txt || error=true
		chmod 600 /mnt/.swap/swapfile >/dev/null 2>>error.txt || error=true
		mkswap /mnt/.swap/swapfile >/dev/null 2>>error.txt || error=true
		swapon /mnt/.swap/swapfile >/dev/null 2>>error.txt || error=true
	fi
	mount "$bootdev" /mnt/boot >/dev/null 2>>error.txt || error=true
	showresult

	# Installing and running reflector to generate mirrorlist
	printm 'Installing and running reflector to generate mirrorlist'
	pacman --noconfirm --needed -Sy reflector >/dev/null 2>>error.txt || error=true
	reflector -l 50 -p http -p https --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>>error.txt || error=true
	showresult

	# Installing base to disk
	printm 'Installing base to disk'
	pacstrap /mnt base linux linux-firmware btrfs-progs >/dev/null 2>>error.txt || error=true
	genfstab -U /mnt >> /mnt/etc/fstab 2>>error.txt || error=true
	cp "${0}" /mnt/root/archer.sh >/dev/null 2>>error.txt || error=true
	chmod 755 /mnt/root/archer.sh >/dev/null 2>>error.txt || error=true
	showresult

	# Downloading pkglist.txt
	if [ "$pkglist" != "" ] ; then
		printm 'Downloading pkglist.txt'
		curl -o /mnt/root/pkglist.txt -sL "$pkglist" >/dev/null 2>>error.txt || error=true
		showresult
	elif [ -f pkglist.txt ] ; then
		printm 'Copying pkglist.txt'
		cp pkglist.txt /mnt/root/pkglist.txt >/dev/null 2>>error.txt || error=true
		showresult
	fi

	# Running arch-chroot
	printm 'Running arch-chroot'
	echo
	arch-chroot /mnt /root/archer.sh --chroot
	rm /mnt/root/archer.sh
	[ -f /mnt/root/pkglist.txt ] && rm /mnt/root/pkglist.txt
	[ -f /mnt/error.txt ] && cat /mnt/error.txt >>error.txt && rm /mnt/error.txt
}

# Run after arch-chroot
aichroot() {
	# Setting up locale and keyboard
	printm 'Setting up locale and keyboard'
	sed -i '/#'${locale}'.UTF-8/s/^#//g' /etc/locale.gen
	sed -i '/#'${language}'.UTF-8/s/^#//g' /etc/locale.gen
	sed -i '/#en_US.UTF-8/s/^#//g' /etc/locale.gen # For safety reasons
	locale-gen >/dev/null 2>>error.txt || error=true
	printf "KEYMAP=%s\n" "${keymap}" > /etc/vconsole.conf
	printf "LANG=%s.UTF-8\n" "${language}" > /etc/locale.conf
	printf "LC_COLLATE=C\n" >> /etc/locale.conf
	printf "LC_ADDRESS=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_CTYPE=%s.UTF-8\n" "${language}" >> /etc/locale.conf
	printf "LC_IDENTIFICATION=%s.UTF-8\n" "${language}" >> /etc/locale.conf
	printf "LC_MEASUREMENT=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_MESSAGES=%s.UTF-8\n" "${language}" >> /etc/locale.conf
	printf "LC_MONETARY=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_NAME=%s.UTF-8\n" "${language}" >> /etc/locale.conf
	printf "LC_NUMERIC=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_PAPER=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_TELEPHONE=%s.UTF-8\n" "${locale}" >> /etc/locale.conf
	printf "LC_TIME=%s.UTF-8\n" "${language}" >> /etc/locale.conf
	showresult

	# Setting timezone and adjtime
	printm 'Setting timezone and adjtime'
	ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime >/dev/null 2>>error.txt || error=true
	hwclock --systohc >/dev/null 2>>error.txt || error=true
	showresult

	# Setting hostname
	printm 'Setting hostname'
	printf "%s\n" "$hostname" > /etc/hostname
	printf "127.0.0.1\tlocalhost\n" > /etc/hosts
	printf "::1\t\tlocalhost\tip6-localhost\tip6-loopback\n" >> /etc/hosts
	printf "127.0.1.1\t%s\t%s.local\n" "$hostname" "$hostname" >> /etc/hosts
	showresult

	# Creating new initramfs
	printm 'Creating new initramfs'
	sed -i '/^MODULES=/s/=()/=(btrfs)/' /etc/mkinitcpio.conf >/dev/null 2>>error.txt || error=true
	if [ "$encrypt" = true ] ; then
		sed -i '/^HOOKS=/s/\(filesystems\)/encrypt \1/' /etc/mkinitcpio.conf >/dev/null 2>>error.txt || error=true
		sed -i '/^HOOKS=/s/\(block\)/keyboard keymap \1/' /etc/mkinitcpio.conf >/dev/null 2>>error.txt || error=true
	fi
	mkinitcpio -P >/dev/null 2>>error.txt || error=true
	showresult

	# Installing bootloader
	printm 'Installing bootloader'
	pacman --noconfirm --needed -Sy grub grub-btrfs >/dev/null 2>>error.txt || error=true
	if [ "$encrypt" = true ] ; then
		sed -i '/^GRUB_CMDLINE_LINUX=/s/=""/="cryptdevice=UUID='"$rootid:root"':allow-discards"/' /etc/default/grub >/dev/null 2>>error.txt || error=true
		sed -i 's/^#\?\(GRUB_ENABLE_CRYPTODISK=\).\+/\1y/' /etc/default/grub >/dev/null 2>>error.txt || error=true
	fi
	if [ "$useefi" = true ] ; then
		pacman --noconfirm --needed -Sy efibootmgr >/dev/null 2>>error.txt || error=true
		grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck $device \
			>/dev/null 2>>error.txt || error=true
	else
		grub-install --target=i386-pc --recheck $device >/dev/null 2>>error.txt || error=true
	fi
	grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>>error.txt || error=true
	showresult

	# Reading packages from pkglist.txt
	if [ -f /root/pkglist.txt ] ; then
		printm 'Reading packages from pkglist.txt'
		reposorted="$(cat <(pacman -Slq) <(pacman -Sgq) | sort)"
		pkgsorted="$(sort /root/pkglist.txt | grep -o '^[^#]*' | grep -v '^-' | sed 's/[ \t]*$//')" || error=true
		packages=$(comm -12 <(echo "$reposorted") <(echo "$pkgsorted") | tr '\n' ' ') || error=true
		aurpackages=$(comm -13 <(echo "$reposorted") <(echo "$pkgsorted") | tr '\n' ' ') || error=true
		rempackages=$(awk '/^-/ {print substr($1,2)}' /root/pkglist.txt | tr '\n' ' ') || error=true
		showresult
	fi

	# Installing extra packages
	if [[ $packages != "" ]] ; then
		printm 'Installing extra packages'
		pacman --noconfirm --needed -Sy $packages >/dev/null 2>>error.txt || error=true
		showresult
	fi

	# Editing som /etc files
	printm 'Editing som /etc files'
	grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf # Pacman colors
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf # Use all cores for compilation.
	[ -f "/etc/nanorc" ] && sed -i '/^# include / s/^# //' /etc/nanorc # nano syntax highlighting
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf # Disable internal speaker
	# xorg.conf keyboard settings
	mkdir -p /etc/X11/xorg.conf.d/
	printf 'Section "InputClass"
	Identifier "system-keyboard"
	MatchIsKeyboard "on"
	Option "XkbLayout" "%s"
	Option "XkbOptions" "nbsp:none"
EndSection\n' "${keymap}" > /etc/X11/xorg.conf.d/00-keyboard.conf
	showresult

	# Adding user and setting password
	printm 'Adding user and setting password'
	mkdir -p /etc/sudoers.d/
	chmod 750 /etc/sudoers.d/
	echo "root ALL=(ALL) ALL" > /etc/sudoers.d/root
	echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheelnopasswd
	useradd -m -g wheel -s /bin/bash "$username" >/dev/null 2>>error.txt || error=true
	showresult
	passwd $username

	if [ "$installyay" = true ] ; then
		# Installing yay AUR helper
		printm 'Installing yay AUR helper'
		pacman --noconfirm --needed -Sy base-devel git go sudo >/dev/null 2>>error.txt || error=true
		cd /tmp >/dev/null 2>>error.txt || error=true
		sudo -u "$username" git clone https://aur.archlinux.org/yay.git >/dev/null 2>>error.txt || error=true
		cd yay >/dev/null 2>>error.txt || error=true
		sudo -u "$username" makepkg --noconfirm -si >/dev/null 2>>error.txt || error=true
		showresult
		if [[ $aurpackages != "" ]] ; then
			printm 'Installing AUR packages'
			sudo -u "$username" yay -S --noconfirm $aurpackages >/dev/null 2>>error.txt || error=true
			showresult
		fi
	fi

	# Removing unwanted packages
	if [[ $rempackages != "" ]] ; then
		printm 'Removing unwanted packages'
		pacman --noconfirm  -Rsu $(pacman -Qq $rempackages) >/dev/null 2>>error.txt || error=true
		showresult
	fi
	
	# Installing dotfiles from git repo
	if [[ $dotfilesrepo != "" ]] ; then
		printm 'Installing dotfiles from git repo'
		pacman --noconfirm --needed -Sy git sudo >/dev/null 2>>error.txt || error=true
		tempdir=$(mktemp -d) >/dev/null 2>>error.txt || error=true
		chown -R "$username:wheel" "$tempdir" >/dev/null 2>>error.txt || error=true
		sudo -u "$username" git clone --depth 1 "$dotfilesrepo" "$tempdir/dotfiles" >/dev/null 2>>error.txt || error=true
		rm -rf "$tempdir/dotfiles/.git" >/dev/null 2>>error.txt || error=true
		sudo -u "$username" cp -rfT "$tempdir/dotfiles" "/home/$username" >/dev/null 2>>error.txt || error=true
		showresult
	fi

	# Enabeling services
	printm 'Enabeling services (Created symlink "errors" can be ignored)'
	# Services: network manager
	if pacman -Q networkmanager >/dev/null 2>&1 ; then
		systemctl enable NetworkManager.service >/dev/null 2>>error.txt || error=true
		systemctl enable NetworkManager-wait-online.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q connman >/dev/null 2>&1 ; then
		systemctl enable connman.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q wicd >/dev/null 2>&1 ; then
		systemctl enable wicd.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q dhcpcd >/dev/null 2>&1 ; then
		systemctl enable dhcpcd.service >/dev/null 2>>error.txt || error=true
	else
		systemctl enable systemd-networkd.service >/dev/null 2>>error.txt || error=true
		systemctl enable systemd-networkd-wait-online.service >/dev/null 2>>error.txt || error=true
	fi
	# Services: display manager
	if pacman -Q lightdm >/dev/null 2>&1 ; then
		systemctl enable lightdm.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q lxdm >/dev/null 2>&1 ; then
		systemctl enable lxdm.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q gdm >/dev/null 2>&1 ; then
		systemctl enable gdm.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q sddm >/dev/null 2>&1 ; then
		systemctl enable sddm.service >/dev/null 2>>error.txt || error=true
	elif pacman -Q xorg-xdm >/dev/null 2>&1 ; then
		systemctl enable xdm.service >/dev/null 2>>error.txt || error=true
	elif pacman -Qs entrance >/dev/null 2>&1 ; then
		systemctl enable entrance.service >/dev/null 2>>error.txt || error=true
	fi
	# Services: other
	pacman -Q util-linux >/dev/null 2>&1 && \
		systemctl enable fstrim.timer 2>>error.txt || error=true
	pacman -Q bluez >/dev/null 2>&1 && \
		systemctl enable bluetooth.service >/dev/null 2>>error.txt || error=true
	pacman -Q modemmanager >/dev/null 2>&1 && \
		systemctl enable ModemManager.service >/dev/null 2>>error.txt || error=true
	showresult
	rm -f /etc/sudoers.d/wheelnopasswd >/dev/null 2>>error.txt

}

# Printing OK/ERROR
showresult() {
	if [ "$error" ] ; then
		printf ' \e[1;31m[ERROR]\e[m\n'
		cat error.txt 2>/dev/null
		printf '\e[1mExit installer? [y/N]\e[m\n'
		read exit < /dev/tty
		[ "$exit" != "${exit#[Yy]}" ] && exit
	else
		printf ' \e[1;32m[OK]\e[m\n'
	fi
	rm error.txt >/dev/null 2>&1
	unset error
}
# Padding
width=$(($(tput cols)-15))
padding=$(printf '.%.0s' {1..500})
printm() {
	printf '%-'$width'.'$width's' "$1 $padding"
}


if [[ "$1" == "--chroot" ]]; then
	aichroot
else
	aistart
fi
