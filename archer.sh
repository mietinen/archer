#!/usr/bin/env bash

# Archer Archlinux install script
# Setup with EFI/MBR bootloader (GRUB) at 200M /boot/efi partition
#               * btrfs root partition
#                 * @root, @home, @srv, @var, @snap subvolumes
#                 * Auto/manual/none swap file
#
## Copyright (c) 2022 Aleksander Mietinen

# ------------------------------------------------------------------------------
# Some settings
# ------------------------------------------------------------------------------
hostname="archer"       # Machine hostname
username="mietinen"     # Main user
device="/dev/nvme0n1"   # Drive for install (/dev/nvme0n1, /dev/sda, etc)
language="en_GB"        # Language for locale.conf
locale="nb_NO"          # Numbers, messurement, etc. for locale.conf
keymap="no"             # Keymap (localectl list-keymaps)
timezone="Europe/Oslo"  # Timezone (located in /usr/share/zoneinfo/../..)
swapsize="auto"         # Size of swap file in MB (auto=MemTotal, 0=no swap)
snapsub=true            # Create @snap to avoid nested snapshots subvolume
encrypt=true            # Set up dm-crypt/LUKS on root partition
multilib=true           # Enable multilib (true/false)
aurhelper="paru-bin"    # Install AUR helper (yay,paru.. blank for none)
                        # Also installs: base-devel git

# ------------------------------------------------------------------------------
# pkglist.txt for extra packages (none will use pkglist.txt from local directory)
# ------------------------------------------------------------------------------
pkglist=(
    "https://raw.githubusercontent.com/mietinen/archer/main/pkg/pkglist.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/main/pkg/p14s.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/main/pkg/gaming.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/main/pkg/pentest.txt"
)

# ------------------------------------------------------------------------------
# Dotfiles git repo (git bare style)
# ------------------------------------------------------------------------------
dotfilesrepo=(
    "https://github.com/mietinen/dots.git"
)


# ------------------------------------------------------------------------------
# End of settings
# No need edit from here
# ------------------------------------------------------------------------------
shopt -s extglob

# ------------------------------------------------------------------------------
# EFI and root file system devices
# ------------------------------------------------------------------------------
if [ "${device::8}" == "/dev/nvm" ] ; then
    if [ -d "/sys/firmware/efi" ] ; then
        efidev="${device}p1"
        rootdev="${device}p2"
    else
        rootdev="${device}p1"
    fi
else
    if [ -d "/sys/firmware/efi" ] ; then
        efidev="${device}1"
        rootdev="${device}2"
    else
        rootdev="${device}1"
    fi
fi

# ------------------------------------------------------------------------------
# Set size of swap file same as total memory if set as auto
# ------------------------------------------------------------------------------
[ "$swapsize" = "auto" ] && \
    swapsize=$((($(grep MemTotal /proc/meminfo | awk '{print $2}')+500)/1000))

# ------------------------------------------------------------------------------
# Run at launch
# ------------------------------------------------------------------------------
archer_check() {
    if [ ! "$(uname -n)" = "archiso" ]; then
        echo "This script is ment to be run from the Archlinux live medium."
        exit
    fi
    if [ "$(id -u)" -ne 0 ]; then
         echo "This script must be run as root."
         exit
    fi
}

# ------------------------------------------------------------------------------
# Setting up keyboard and clock
# ------------------------------------------------------------------------------
archer_keyclock() {
    printm 'Setting up keyboard and clock'
    _s loadkeys "$keymap"
    _s timedatectl set-ntp true
    showresult
}

# ------------------------------------------------------------------------------
# Setting up partitions
# ------------------------------------------------------------------------------
archer_partition() {
    printm 'Setting up partitions'
    if [ -d "/sys/firmware/efi" ] ; then
        _s parted -s "$device" mklabel gpt \
            mkpart esp 0% 300MiB \
            mkpart primary 300MiB 100% \
            set 1 esp on
    else
        _s parted -s "$device" mklabel msdos \
            mkpart primary 0% 100%
    fi
    showresult
}

# ------------------------------------------------------------------------------
# Setting up encryption
# ------------------------------------------------------------------------------
archer_encrypt() {
    mapper="$rootdev"
    if [ "$encrypt" = true ] ; then
        printm 'Setting up encryption'
        echo
        _s dd bs=512 count=4 if=/dev/random of=.root.keyfile iflag=fullblock
        _e cryptsetup -q luksFormat --type luks1 --align-payload=8192 -s 256 -i 256 -c aes-xts-plain64 "$rootdev" .root.keyfile
        _e cryptsetup -q open "$rootdev" root --key-file .root.keyfile
        _e cryptsetup -q luksAddKey "$rootdev" -i 256 --key-file .root.keyfile
        mapper="/dev/mapper/root"
        printm 'Encryption setup'
        showresult
    fi
}

# ------------------------------------------------------------------------------
# Formating partitions
# ------------------------------------------------------------------------------
archer_format() {
    printm 'Formating partitions'
    if [ -d "/sys/firmware/efi" ] ; then
        _s mkfs.vfat "$efidev"
    fi
    _s mkfs.btrfs -f "$mapper"

    _s mount "$mapper" /mnt
    _s btrfs subvolume create /mnt/@root
    _s btrfs subvolume create /mnt/@home
    _s btrfs subvolume create /mnt/@srv
    _s btrfs subvolume create /mnt/@var
    [ "$snapsub" = true ] && _s btrfs subvolume create /mnt/@snap
    _s umount /mnt
    showresult
}

# ------------------------------------------------------------------------------
# Mounting partitions
# ------------------------------------------------------------------------------
archer_mount() {
    printm 'Mounting partitions'
    opt="compress=zstd"
    _s mount -o $opt,subvol=@root "$mapper" /mnt
    _s mkdir -p /mnt/{home,srv,var,.snapshots}
    _s mount -o $opt,subvol=@home "$mapper" /mnt/home
    _s mount -o $opt,subvol=@srv "$mapper" /mnt/srv
    _s mount -o nodatacow,subvol=@var "$mapper" /mnt/var
    [ "$snapsub" = true ] && \
        _s mount -o $opt,subvol=@snap "$mapper" /mnt/.snapshots
    if [ "$swapsize" != "0" ] ; then
        _s btrfs filesystem mkswapfile --size "${swapsize}m" --uuid clear /mnt/var/swapfile
        _s swapon /mnt/var/swapfile
    fi
    if [ -d "/sys/firmware/efi" ] ; then
        _s mkdir -p /mnt/boot/efi
        _s mount "$efidev" /mnt/boot/efi
    fi
    showresult
}

# ------------------------------------------------------------------------------
# Installing and running reflector to generate mirrorlist
# ------------------------------------------------------------------------------
archer_reflector() {
    printm 'Installing and running reflector to generate mirrorlist'
    _s pacman --noconfirm --needed -Sy reflector
    _s reflector -a 48 --score 50 --sort score --save /etc/pacman.d/mirrorlist
    showresult
}

# ------------------------------------------------------------------------------
# Downloading pkglist.txt
# ------------------------------------------------------------------------------
archer_pkgfetch() {
    mkdir -p /mnt/root
    if [ ${#pkglist[@]} -gt 0 ] ; then
        printm 'Downloading pkglist.txt'
        for pkg in "${pkglist[@]}" ; do
            _e echo "# $pkg" >>/mnt/root/pkglist.txt
            _e curl -sL "$pkg" >>/mnt/root/pkglist.txt
            _e echo >>/mnt/root/pkglist.txt
        done
        showresult
    fi

    if [ ! -r /mnt/root/pkglist.txt ] && [ -r pkglist.txt ] ; then
        printm 'Copying pkglist.txt'
        _s cp pkglist.txt /mnt/root/pkglist.txt
        showresult
    fi
}

# ------------------------------------------------------------------------------
# Installing base to disk
# ------------------------------------------------------------------------------
archer_pacstrap() {
    printm 'Installing base to disk'
    [ -r /mnt/root/pkglist.txt ] && \
        kernel="$(_e grep -oE '^[^(#|[:space:])]*' /mnt/root/pkglist.txt | grep -E '^linux(-hardened|-lts|-zen)?$' | tr '\n' ' ')"
    _s pacstrap /mnt base ${kernel:-linux} linux-firmware btrfs-progs sudo
    _e genfstab -U /mnt >> /mnt/etc/fstab
    showresult
}

# ------------------------------------------------------------------------------
# Copy script to /mnt/root/archer.sh and running arch-chroot
# Cleaning up files in /mnt/root
# ------------------------------------------------------------------------------
archer_chroot() {
    printm 'Running arch-chroot'
    _s install -Dm755 "$0" /mnt/root/archer.sh
    if [ -r .root.keyfile ] ; then
        _s mv .root.keyfile /mnt/boot/.root.keyfile
        _s chmod 600 /mnt/boot/.root.keyfile
    fi
    showresult
    arch-chroot /mnt /root/archer.sh --chroot
    rm -f /mnt/root/archer.sh \
        /mnt/root/pkglist.txt \
        /mnt/err.o
}

# ------------------------------------------------------------------------------
# Run after arch-chroot
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Setting up locale and keyboard
# ------------------------------------------------------------------------------
archer_locale() {
    printm 'Setting up locale and keyboard'
    _s sed -i '/^#'$locale'/s/^#//g' /etc/locale.gen
    _s sed -i '/^#'$language'/s/^#//g' /etc/locale.gen
    _s sed -i '/^#en_US/s/^#//g' /etc/locale.gen
    _s locale-gen
    _e printf "KEYMAP=%s\n" "$keymap" > /etc/vconsole.conf
    _e printf "LANG=%s.UTF-8\n" "$language" > /etc/locale.conf
    _e printf "LC_COLLATE=C\n" >> /etc/locale.conf
    _e printf "LC_ADDRESS=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_CTYPE=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_IDENTIFICATION=%s.UTF-8\n" "$language" >> /etc/locale.conf
    _e printf "LC_MEASUREMENT=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_MESSAGES=%s.UTF-8\n" "$language" >> /etc/locale.conf
    _e printf "LC_MONETARY=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_NAME=%s.UTF-8\n" "$language" >> /etc/locale.conf
    _e printf "LC_NUMERIC=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_PAPER=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_TELEPHONE=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    _e printf "LC_TIME=%s.UTF-8\n" "$language" >> /etc/locale.conf
    showresult
}

# ------------------------------------------------------------------------------
# Setting timezone and adjtime
# ------------------------------------------------------------------------------
archer_timezone() {
    printm 'Setting timezone and adjtime'
    _s ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
    _s hwclock --systohc
    showresult
}

# ------------------------------------------------------------------------------
# Setting hostname
# ------------------------------------------------------------------------------
archer_hostname() {
    printm 'Setting hostname'
    _e printf "%s\n" "$hostname" > /etc/hostname
    _e printf "%-15s %s\n" "127.0.0.1" "localhost" > /etc/hosts
    _e printf "%-15s %-15s %-15s %-15s\n" "::1" "localhost" "ip6-localhost" "ip6-loopback" >> /etc/hosts
    _e printf "%-15s %-15s %-15s %-15s\n" "127.0.1.1" "$hostname" "${hostname}.home.arpa" >> /etc/hosts
    showresult
}

# ------------------------------------------------------------------------------
# Creating new initramfs
# ------------------------------------------------------------------------------
archer_initramfs() {
    printm 'Creating new initramfs'
    _s sed -i '/^MODULES=/s/=()/=(btrfs)/' /etc/mkinitcpio.conf
    if [ "$encrypt" = true ] ; then
        _s sed -i '/^HOOKS=/s/\(filesystems\)/encrypt \1/' /etc/mkinitcpio.conf
        _s sed -i '/^HOOKS=/s/\(autodetect\)/keyboard keymap \1/' /etc/mkinitcpio.conf
        _s sed -i ':s;/^HOOKS=/s/\(\<\S*\>\)\(.*\)\<\1\>/\1\2/g;ts;/^HOOKS=/s/  */ /g' /etc/mkinitcpio.conf
        _s sed -i '/^FILES=/s/=()/=(\/boot\/.root.keyfile)/' /etc/mkinitcpio.conf
    fi
    _s mkinitcpio -P
    _s chmod 600 /boot/initramfs-linux*
    showresult
}

# ------------------------------------------------------------------------------
# Changes to pacman.conf and makepkg.conf
# ------------------------------------------------------------------------------
archer_pacconf() {
    printm 'Changes to pacman.conf and makepkg.conf'
    _s sed -i "s/^#\(Color\)/\1/" /etc/pacman.conf
    _s sed -i "s/^#\(ParallelDownloads\)/\1/" /etc/pacman.conf
    _s sed -i "s/^#\?\(MAKEFLAGS.*\)-j[0-9]\+\(.*\)/\1-j$(nproc)\2/" /etc/makepkg.conf
    _s sed -i '/^OPTIONS/s/\([ (]\)debug/\1!debug/' /etc/makepkg.conf
    if [ "$multilib" = true ] ; then
        _s sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    fi
    # Move DBpath out of /var, to make it a part of @root snapshots
    _s mv /var/lib/pacman/ /usr/lib/pacman/
    _s ln -sf ../../usr/lib/pacman/ /var/lib/pacman
    _s sed -i 's/^#\?\(DBPath\s\+=\).\+/\1 \/usr\/lib\/pacman\//' /etc/pacman.conf
    showresult
}

# ------------------------------------------------------------------------------
# Installing bootloader
# ------------------------------------------------------------------------------
archer_bootloader() {
    printm 'Installing bootloader'
    _s pacman --noconfirm --needed -Sy grub grub-btrfs inotify-tools
    if [ "$encrypt" = true ] ; then
        rootid=$(blkid --output export "$rootdev" | sed --silent 's/^UUID=//p')
        _s sed -i '/^GRUB_CMDLINE_LINUX=/s/=""/="cryptdevice=UUID='"$rootid"':root:allow-discards cryptkey=rootfs:\/boot\/.root.keyfile"/' /etc/default/grub
        _s sed -i 's/^#\?\(GRUB_ENABLE_CRYPTODISK=\).\+/\1y/' /etc/default/grub
    fi
    if [ -d "/sys/firmware/efi" ] ; then
        _s pacman --noconfirm --needed -S efibootmgr
        _s grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck "$device"
    else
        _s grub-install --target=i386-pc --recheck "$device"
    fi

    vendor="$(awk '/^vendor_id/ {print $NF;exit}' /proc/cpuinfo)"
    case "${vendor,,}" in
        *intel*) _s pacman --noconfirm --needed -S intel-ucode ;;
        *amd*) _s pacman --noconfirm --needed -Sy amd-ucode ;;
    esac

    _s grub-mkconfig -o /boot/grub/grub.cfg
    showresult
}

# ------------------------------------------------------------------------------
# Reading packages from pkglist.txt
# ------------------------------------------------------------------------------
archer_readpkg() {
    if [ -r /root/pkglist.txt ] ; then
        printm 'Reading packages from pkglist.txt'
        repo="$(cat <(pacman -Slq) <(pacman -Sgq) | sort -u 2>>err.o)" || err=true
        list="$(grep -oE '^[^(#|[:space:])]*' /root/pkglist.txt | sort -u 2>>err.o)" || err=true
        packages=$(comm -12 <(echo "$repo") <(echo "$list") | tr '\n' ' ' 2>>err.o) || err=true
        aurpackages=$(comm -13 <(echo "$repo") <(echo "$list") | tr '\n' ' ' 2>>err.o) || err=true
        showresult
    fi
}

# ------------------------------------------------------------------------------
# Installing extra packages
# ------------------------------------------------------------------------------
archer_pacinstall() {
    if [ -n "$packages" ] ; then
        printm 'Installing extra packages'
        # Can be needed if iso is old.
        _s pacman --noconfirm -Sy archlinux-keyring
        # --ask 4: ALPM_QUESTION_CONFLICT_PKG = (1 << 2)
        _s pacman --noconfirm --needed --ask 4 -S $packages
        showresult
    fi
}

# ------------------------------------------------------------------------------
# Editing som /etc files
# ------------------------------------------------------------------------------
archer_etcconf() {
    printm 'Editing som /etc files'
    # Disable internal speaker
    _e echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
    # xorg.conf keyboard settings
    if pacman -Q xorg-server &>/dev/null ; then
        mkdir -p /etc/X11/xorg.conf.d/
        _e cat <<EOF >/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${keymap}"
    Option "XkbOptions" "nbsp:none"
EndSection
EOF
    fi
    # .local hostname resolution
    if pacman -Q nss-mdns &>/dev/null ; then
        grep -e "hosts:.*mdns_minimal" /etc/nsswitch.conf &>/dev/null || \
            _s sed -i '/^hosts:/s/\(resolve\|dns\)/mdns_minimal \[NOTFOUND=return\] \1/' /etc/nsswitch.conf
    fi
    if pacman -Q mlocate &>/dev/null ; then
        grep -e "PRUNENAMES.*\.snapshots" /etc/updatedb.conf &>/dev/null || \
            _s sed -i '/^PRUNENAMES/s/"\(.*\)"/"\1 .snapshots"/' /etc/updatedb.conf
    fi
    showresult
}

# ------------------------------------------------------------------------------
# Adding user and setting password
# ------------------------------------------------------------------------------
archer_user() {
    printm 'Adding user and setting password'
    mkdir -p /etc/sudoers.d/
    _s chmod 750 /etc/sudoers.d/
    _e echo "root ALL=(ALL) ALL" > /etc/sudoers.d/root
    _e echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
    # removed later
    _e echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheelnopasswd
    _s useradd -m -G wheel -s /bin/bash "$username"
    # Other groups
    if pacman -Q libvirt &>/dev/null ; then
        _s usermod -aG libvirt "$username"
    fi
    if pacman -Q wireshark-cli &>/dev/null ; then
        _s usermod -aG wireshark "$username"
    fi
    showresult
    passwd "$username"
}

# ------------------------------------------------------------------------------
# Installing AUR helper and packages
# ------------------------------------------------------------------------------
archer_aurinstall() {
    if [ -n "$aurhelper" ] ; then
        # Installing AUR helper
        printm "Installing AUR helper ($aurhelper)"
        _s pacman --noconfirm --needed -S base-devel git
        _s cd /tmp
        _s sudo -u "$username" git clone "https://aur.archlinux.org/$aurhelper.git"
        _s cd "$aurhelper"
        _s sudo -u "$username" makepkg --noconfirm -si
        showresult
        if [ -n "$aurpackages" ] ; then
            printm 'Installing AUR packages (Failures can be checked out manually later)'
            for aur in $aurpackages; do
                _s sudo -u "$username" "${aurhelper%-@(bin|git)}" -S --noconfirm "$aur"
            done
            showresult
        fi
    fi
}

# ------------------------------------------------------------------------------
# Installing dotfiles from git repo
# ------------------------------------------------------------------------------
archer_dotfiles() {
    if [ ${#dotfilesrepo[@]} -gt 0 ] ; then
        printm 'Installing dotfiles from git repo'
        _s pacman --noconfirm --needed -S git
        for repo in "${dotfilesrepo[@]}" ; do
            tempdir="$(mktemp -d)" || err=true
            _s chown -R "$username:$username" "$tempdir"
            _s sudo -u "$username" git clone --depth 1 "$repo" "$tempdir/dotfiles"
            _s rm -rf "$tempdir/dotfiles/.git"
            _s sudo -u "$username" cp -rfT "$tempdir/dotfiles" "/home/$username"
        done
        showresult
    fi
}

# ------------------------------------------------------------------------------
# Enabeling installed services
# ------------------------------------------------------------------------------
archer_services() {
    printm 'Enabeling services (Created symlink "errors" can be ignored)'
    # Services: network manager
    if pacman -Q networkmanager &>/dev/null ; then
        _s systemctl enable NetworkManager.service
        _s systemctl enable NetworkManager-wait-online.service
        _s systemctl enable systemd-resolved.service
        umount /etc/resolv.conf 2>/dev/null
        _s ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    elif pacman -Q connman &>/dev/null ; then
        _s systemctl enable connman.service

    elif pacman -Q wicd &>/dev/null ; then
        _s systemctl enable wicd.service

    elif pacman -Q dhcpcd &>/dev/null ; then
        _s systemctl enable dhcpcd.service

    else
        eth="$(basename /sys/class/net/en*)"
        wifi="$(basename /sys/class/net/wl*)"
        [ -d "/sys/class/net/$eth" ] && \
            printf "[Match]\nName=%s\n\n[Network]\nDHCP=yes\n\n[DHCP]\nRouteMetric=10" "$eth" \
            > /etc/systemd/network/20-wired.network
        [ -d "/sys/class/net/$wifi" ] && \
            printf "[Match]\nName=%s\n\n[Network]\nDHCP=yes\n\n[DHCP]\nRouteMetric=20" "$wifi" \
            > /etc/systemd/network/25-wireless.network
        _s systemctl enable systemd-networkd.service
        _s systemctl enable systemd-networkd-wait-online.service
        _s systemctl enable systemd-resolved.service
        umount /etc/resolv.conf 2>/dev/null
        _s ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi

    # Services: display manager
    if pacman -Q ly &>/dev/null ; then
        _e cat <<EOF > /etc/pam.d/ly
#%PAM-1.0
auth        include     system-login
-auth       optional    pam_gnome_keyring.so
-auth       optional    pam_kwallet5.so
account     include     system-login
password    include     system-login
session     include     system-login
-session    optional    pam_gnome_keyring.so auto_start
-session    optional    pam_kwallet5.so auto_start
EOF
        _s systemctl enable ly.service
    elif pacman -Q lightdm &>/dev/null ; then
        _s systemctl enable lightdm.service

    elif pacman -Q lxdm &>/dev/null ; then
        _s systemctl enable lxdm.service

    elif pacman -Q gdm &>/dev/null ; then
        _s systemctl enable gdm.service

    elif pacman -Q sddm &>/dev/null ; then
        _s systemctl enable sddm.service

    elif pacman -Q xorg-xdm &>/dev/null ; then
        _s systemctl enable xdm.service

    elif pacman -Qs entrance &>/dev/null ; then
        _s systemctl enable entrance.service
    fi

    # Services: other
    if pacman -Q util-linux &>/dev/null ; then
        _s systemctl enable fstrim.timer
    fi

    if pacman -Q bluez &>/dev/null ; then
        _s systemctl enable bluetooth.service
    fi

    if pacman -Q modemmanager &>/dev/null ; then
        _s systemctl enable ModemManager.service
    fi

    if pacman -Q ufw &>/dev/null ; then
        _s systemctl enable ufw.service
    fi

    if pacman -Q libvirt &>/dev/null ; then
        _s systemctl enable libvirtd.service
    fi

    if pacman -Q avahi &>/dev/null ; then
        _s sed -i 's/^#\?\(MulticastDNS=\).\+/\1no/' /etc/systemd/resolved.conf
        _s systemctl enable avahi-daemon.service
    fi

    if pacman -Q cups &>/dev/null ; then
        _s systemctl enable cups.service
    fi

    if pacman -Q autorandr &>/dev/null ; then
        _s systemctl enable autorandr.service
    fi

    if pacman -Q auto-cpufreq &>/dev/null ; then
        _s systemctl enable auto-cpufreq.service
    fi
    showresult
}

# ------------------------------------------------------------------------------
# Short function to silent command outputs
# ------------------------------------------------------------------------------
_s() { "$@" >/dev/null 2>>err.o || err=true; }
_e() { "$@" 2>>err.o || err=true; }

# ------------------------------------------------------------------------------
# Printing OK/ERROR
# ------------------------------------------------------------------------------
showresult() {
    if [ "$err" ] ; then
        printf ' \e[1;31m[ERROR]\e[m\n'
        cat err.o 2>/dev/null
        printf '\e[1mExit installer? [y/N]\e[m\n'
        read -r exit
        [ "$exit" != "${exit#[Yy]}" ] && exit
    else
        printf ' \e[1;32m[OK]\e[m\n'
    fi
    rm -f err.o
    unset err
}

# ------------------------------------------------------------------------------
# Padding
# ------------------------------------------------------------------------------
width=$(($(tput cols)-15))
padding=$(printf '.%.0s' {1..500})
printm() {
    printf "%-${width}.${width}s" "$1 $padding"
}

if [ "$1" != "--chroot" ]; then
    archer_check
    archer_keyclock
    archer_partition
    archer_encrypt
    archer_format
    archer_mount
    # archer_reflector
    archer_pkgfetch
    archer_pacstrap
    archer_chroot
else
    archer_locale
    archer_timezone
    archer_hostname
    archer_initramfs
    archer_pacconf
    archer_bootloader
    archer_readpkg
    archer_pacinstall
    archer_etcconf
    archer_user
    archer_aurinstall
    archer_dotfiles
    archer_services
    rm -f /etc/sudoers.d/wheelnopasswd
fi
