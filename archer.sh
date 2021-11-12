#!/usr/bin/env bash

# Archer Archlinux install script
# Setup with EFI/MBR bootloader (GRUB) at 200M /efi partition
#               * btrfs root partition
#                 * @root, @home, @srv, @var, @swap subvolumes
#                 * Auto/manual/none swap file
#
## license: LGPL-3.0 (http://opensource.org/licenses/lgpl-3.0.html)

# Some settings
hostname="archer"       # Machine hostname
username="mietinen"     # Main user
device="/dev/nvme0n1"   # Drive for install (/dev/nvme0n1, /dev/sda, etc)
language="en_GB"        # Language for locale.conf
locale="nb_NO"          # Numbers, messurement, etc. for locale.conf
keymap="no"             # Keymap (localectl list-keymaps)
timezone="Europe/Oslo"  # Timezone (located in /usr/share/zoneinfo/../..)
swapsize="auto"         # Size of swap file in MB (auto=MemTotal, 0=no swap)
encrypt=true            # Set up dm-crypt/LUKS on root partition
multilib=true           # Enable multilib (true/false)
aurhelper="paru-bin"    # Install AUR helper (yay,paru.. blank for none)
                        # Also installs: base-devel git

# pkglist.txt for extra packages (none will use pkglist.txt from local directory)
pkglist=(
    "https://raw.githubusercontent.com/mietinen/archer/master/pkg/pkglist.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/master/pkg/desktop.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/master/pkg/carbon.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/master/pkg/gaming.txt"
    # "https://raw.githubusercontent.com/mietinen/archer/master/pkg/pentest.txt"
)

# Dotfiles git repo (blank for none)
dotfilesrepo=(
    "https://github.com/mietinen/shell.git"
    # "https://github.com/mietinen/desktop.git"
)


# -------------------
#  No edit from here
# -------------------

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

# Set size of swap file same as total memory if set as auto
[ "$swapsize" = "auto" ] && \
    swapsize=$((($(grep MemTotal /proc/meminfo | awk '{print $2}')+500)/1000))

# Run at launch
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

# Setting up keyboard and clock
archer_keyclock() {
    printm 'Setting up keyboard and clock'
    loadkeys "$keymap" \
        >/dev/null 2>>err.o || err=true
    timedatectl set-ntp true \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Setting up partitions
archer_partition() {
    printm 'Setting up partitions'
    if [ -d "/sys/firmware/efi" ] ; then
        parted -s "$device" mklabel gpt \
            >/dev/null 2>>err.o || err=true
        sgdisk "$device" -n=1:0:+200M -t=1:ef00 \
            >/dev/null 2>>err.o || err=true
        sgdisk "$device" -n=2:0:0 \
            >/dev/null 2>>err.o || err=true
    else
        parted -s "$device" mklabel msdos \
            >/dev/null 2>>err.o || err=true
        echo -e "n\np\n\n\n\nw" | fdisk "$device" \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
}

# Setting up encryption
archer_encrypt() {
    mapper="$rootdev"
    if [ "$encrypt" = true ] ; then
        printm 'Setting up encryption'
        echo
        cryptsetup -q luksFormat --type luks1 --align-payload=8192 -s 256 -c aes-xts-plain64 "$rootdev" .root.keyfile \
            2>>err.o || err=true
        cryptsetup -q open "$rootdev" root --key-file .root.keyfile \
            2>>err.o || err=true
        cryptsetup -q luksAddKey "$rootdev" \
            2>>err.o || err=true
        mapper="/dev/mapper/root"
        printm 'Encryption setup'
        showresult
    fi
}

# Formating partitions
archer_format() {
    printm 'Formating partitions'
    if [ -d "/sys/firmware/efi" ] ; then
        mkfs.vfat "$efidev" \
            >/dev/null 2>>err.o || err=true
    fi
    mkfs.btrfs -f "$mapper" \
        >/dev/null 2>>err.o || err=true

    mount "$mapper" /mnt \
        >/dev/null 2>>err.o || err=true
    btrfs subvolume create /mnt/@root \
        >/dev/null 2>>err.o || err=true
    btrfs subvolume create /mnt/@home \
        >/dev/null 2>>err.o || err=true
    btrfs subvolume create /mnt/@srv \
        >/dev/null 2>>err.o || err=true
    btrfs subvolume create /mnt/@var \
        >/dev/null 2>>err.o || err=true
    if [ "$swapsize" != "0" ] ; then
        btrfs subvolume create /mnt/@swap \
            >/dev/null 2>>err.o || err=true
    fi
    umount /mnt \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Mounting partitions
archer_mount() {
    printm 'Mounting partitions'
    mount -o subvol=@root "$mapper" /mnt \
        >/dev/null 2>>err.o || err=true
    mkdir -p /mnt/{efi,home,srv,var/cache,var/log,var/tmp} \
        >/dev/null 2>>err.o || err=true
    mount -o subvol=@home "$mapper" /mnt/home \
        >/dev/null 2>>err.o || err=true
    mount -o subvol=@srv "$mapper" /mnt/srv \
        >/dev/null 2>>err.o || err=true
    mount -o nodatacow,subvol=@var "$mapper" /mnt/var \
        >/dev/null 2>>err.o || err=true
    if [ "$swapsize" != "0" ] ; then
        mkdir -p /mnt/.swap \
            >/dev/null 2>>err.o || err=true
        mount -o nodatacow,subvol=@swap "$mapper" /mnt/.swap \
            >/dev/null 2>>err.o || err=true
        truncate -s 0 /mnt/.swap/swapfile \
            >/dev/null 2>>err.o || err=true
        chattr +C /mnt/.swap/swapfile \
            >/dev/null 2>>err.o || err=true
        btrfs property set /mnt/.swap/swapfile compression none \
            >/dev/null 2>>err.o || err=true
        dd if=/dev/zero of=/mnt/.swap/swapfile bs=1M count="$swapsize" \
            >/dev/null 2>>err.o || err=true
        chmod 600 /mnt/.swap/swapfile \
            >/dev/null 2>>err.o || err=true
        mkswap /mnt/.swap/swapfile \
            >/dev/null 2>>err.o || err=true
        swapon /mnt/.swap/swapfile \
            >/dev/null 2>>err.o || err=true
    fi
    if [ -d "/sys/firmware/efi" ] ; then
        mount "$efidev" /mnt/efi \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
}

# Installing and running reflector to generate mirrorlist
archer_reflector() {
    printm 'Installing and running reflector to generate mirrorlist'
    pacman --noconfirm -Sy reflector \
        >/dev/null 2>>err.o || err=true
    reflector -l 50 -p http,https --sort rate --save /etc/pacman.d/mirrorlist \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Installing base to disk
archer_pacstrap() {
    printm 'Installing base to disk'
    pacstrap /mnt base linux linux-firmware btrfs-progs sudo \
        >/dev/null 2>>err.o || err=true
    genfstab -U /mnt >> /mnt/etc/fstab \
        2>>err.o || err=true
    showresult
}

# Downloading pkglist.txt
archer_pkgfetch() {
    if [ ${#pkglist[@]} -gt 0 ] ; then
        printm 'Downloading pkglist.txt'
        for pkg in "${pkglist[@]}" ; do
            echo "# $pkg" >>/mnt/root/pkglist.txt
            curl -sL "$pkg" >>/mnt/root/pkglist.txt \
                2>>err.o || err=true
            echo >>/mnt/root/pkglist.txt
        done
        showresult
    fi

    if [ ! -r "/mnt/root/pkglist.txt" ] && [ -r "pkglist.txt" ] ; then
        printm 'Copying pkglist.txt'
        cp pkglist.txt /mnt/root/pkglist.txt \
            >/dev/null 2>>err.o || err=true
        showresult
    fi
}

# Copy script to /mnt/root/archer.sh and running arch-chroot
# Cleaning up files in /mnt/root
archer_chroot() {
    printm 'Running arch-chroot'
    cp "$0" /mnt/root/archer.sh \
        >/dev/null 2>>err.o || err=true
    chmod 755 /mnt/root/archer.sh \
        >/dev/null 2>>err.o || err=true
    if [ -r .root.keyfile ] ; then
        mv .root.keyfile /mnt/boot/.root.keyfile \
            >/dev/null 2>>err.o || err=true
        chmod 600 /mnt/boot/.root.keyfile \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
    arch-chroot /mnt /root/archer.sh --chroot
    rm -f /mnt/root/archer.sh \
        /mnt/root/pkglist.txt \
        /mnt/err.o
}

# Run after arch-chroot

# Setting up locale and keyboard
archer_locale() {
    printm 'Setting up locale and keyboard'
    sed -i '/^#'$locale'/s/^#//g' /etc/locale.gen \
        >/dev/null 2>>err.o || err=true
    sed -i '/^#'$language'/s/^#//g' /etc/locale.gen \
        >/dev/null 2>>err.o || err=true
    sed -i '/^#en_US/s/^#//g' /etc/locale.gen \
        >/dev/null 2>>err.o || err=true
    locale-gen \
        >/dev/null 2>>err.o || err=true
    printf "KEYMAP=%s\n" "$keymap" > /etc/vconsole.conf
    printf "LANG=%s.UTF-8\n" "$language" > /etc/locale.conf
    printf "LC_COLLATE=C\n" >> /etc/locale.conf
    printf "LC_ADDRESS=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_CTYPE=%s.UTF-8\n" "$language" >> /etc/locale.conf
    printf "LC_IDENTIFICATION=%s.UTF-8\n" "$language" >> /etc/locale.conf
    printf "LC_MEASUREMENT=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_MESSAGES=%s.UTF-8\n" "$language" >> /etc/locale.conf
    printf "LC_MONETARY=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_NAME=%s.UTF-8\n" "$language" >> /etc/locale.conf
    printf "LC_NUMERIC=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_PAPER=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_TELEPHONE=%s.UTF-8\n" "$locale" >> /etc/locale.conf
    printf "LC_TIME=%s.UTF-8\n" "$language" >> /etc/locale.conf
    showresult
}

# Setting timezone and adjtime
archer_timezone() {
    printm 'Setting timezone and adjtime'
    ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime \
        >/dev/null 2>>err.o || err=true
    hwclock --systohc \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Setting hostname
archer_hostname() {
    printm 'Setting hostname'
    printf "%s\n" "$hostname" > /etc/hostname
    printf "%-15s %s\n" "127.0.0.1" "localhost" > /etc/hosts
    printf "%-15s %-15s %-15s %-15s\n" "::1" "localhost" "ip6-localhost" "ip6-loopback" >> /etc/hosts
    printf "%-15s %-15s %-15s %-15s\n" "127.0.1.1" "$hostname" "${hostname}.home.arpa" >> /etc/hosts
    showresult
}

# Creating new initramfs
archer_initramfs() {
    printm 'Creating new initramfs'
    sed -i '/^MODULES=/s/=()/=(btrfs)/' /etc/mkinitcpio.conf \
        >/dev/null 2>>err.o || err=true
    if [ "$encrypt" = true ] ; then
        sed -i '/^HOOKS=/s/\(filesystems\)/encrypt \1/' /etc/mkinitcpio.conf \
            >/dev/null 2>>err.o || err=true
        sed -i '/^HOOKS=/s/\(autodetect\)/keyboard keymap \1/' /etc/mkinitcpio.conf \
            >/dev/null 2>>err.o || err=true
        sed -i ':s;/^HOOKS=/s/\(\<\S*\>\)\(.*\)\<\1\>/\1\2/g;ts;/^HOOKS=/s/  */ /g' /etc/mkinitcpio.conf \
            >/dev/null 2>>err.o || err=true
        sed -i '/^FILES=/s/=()/=(\/boot\/.root.keyfile)/' /etc/mkinitcpio.conf \
            >/dev/null 2>>err.o || err=true
    fi
    mkinitcpio -P \
        >/dev/null 2>>err.o || err=true
    chmod 600 /boot/initramfs-linux* 2>>err.o || err=true
    showresult
}

# Changes to pacman.conf and makepkg.conf
archer_pacconf() {
    printm 'Changes to pacman.conf and makepkg.conf'
    sed -i "s/^#\(Color\)/\1/" /etc/pacman.conf \
        >/dev/null 2>>err.o || err=true
    sed -i "s/^#\(ParallelDownloads\)/\1/" /etc/pacman.conf \
        >/dev/null 2>>err.o || err=true
    sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf \
        >/dev/null 2>>err.o || err=true
    if [ "$multilib" = true ] ; then
        sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf \
            >/dev/null 2>>err.o || err=true
    fi
    # Move DBpath out of /var, to make it a part of @root snapshots
    mv /var/lib/pacman/ /usr/lib/pacman/ \
        2>>err.o || err=true
    ln -sf ../../usr/lib/pacman/ /var/lib/pacman \
        2>>err.o || err=true
    sed -i 's/^#\?\(DBPath\s\+=\).\+/\1 \/usr\/lib\/pacman\//' /etc/pacman.conf \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Installing bootloader
archer_bootloader() {
    printm 'Installing bootloader'
    pacman --noconfirm --needed -Sy grub grub-btrfs \
        >/dev/null 2>>err.o || err=true
    if [ "$encrypt" = true ] ; then
        rootid=$(blkid --output export "$rootdev" | sed --silent 's/^UUID=//p')
        sed -i '/^GRUB_CMDLINE_LINUX=/s/=""/="cryptdevice=UUID='$rootid':root:allow-discards cryptkey=rootfs:\/boot\/.root.keyfile"/' /etc/default/grub \
            >/dev/null 2>>err.o || err=true
        sed -i 's/^#\?\(GRUB_ENABLE_CRYPTODISK=\).\+/\1y/' /etc/default/grub \
            >/dev/null 2>>err.o || err=true
    fi
    if [ -d "/sys/firmware/efi" ] ; then
        pacman --noconfirm --needed -S efibootmgr \
            >/dev/null 2>>err.o || err=true
        grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck "$device" \
            >/dev/null 2>>err.o || err=true
    else
        grub-install --target=i386-pc --recheck "$device" \
            >/dev/null 2>>err.o || err=true
    fi
    grub-mkconfig -o /boot/grub/grub.cfg \
        >/dev/null 2>>err.o || err=true
    showresult
}

# Reading packages from pkglist.txt
archer_readpkg() {
    if [ -f /root/pkglist.txt ] ; then
        printm 'Reading packages from pkglist.txt'
        reposorted="$(cat <(pacman -Slq) <(pacman -Sgq) | sort -u 2>>err.o)" \
            || err=true
        pkgsorted="$(grep -o '^[^#]*' /root/pkglist.txt | sed 's/[[:space:]]*$//;/^[[:space:]]*$/d' | sort -u 2>>err.o)" \
            || err=true
        packages=$(comm -12 <(echo "$reposorted") <(echo "$pkgsorted") | tr '\n' ' ' 2>>err.o) \
            || err=true
        aurpackages=$(comm -13 <(echo "$reposorted") <(echo "$pkgsorted") | tr '\n' ' ' 2>>err.o) \
            || err=true
        showresult
    fi
}

# Installing extra packages
archer_pacinstall() {
    if [ -n "$packages" ] ; then
        printm 'Installing extra packages'
        # --ask 4: ALPM_QUESTION_CONFLICT_PKG = (1 << 2)
        pacman --noconfirm --needed --ask 4 -S $packages \
            >/dev/null 2>>err.o || err=true
        showresult
    fi
}

# Editing som /etc files
archer_etcconf() {
    printm 'Editing som /etc files'
    # nano syntax highlighting
    [ -f "/etc/nanorc" ] && sed -i '/^# include / s/^# //' /etc/nanorc \
        >/dev/null 2>>err.o || err=true
    # Disable internal speaker
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf \
        2>>err.o || err=true
    # xorg.conf keyboard settings
    mkdir -p /etc/X11/xorg.conf.d/
    printf 'Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "%s"
    Option "XkbOptions" "nbsp:none"
EndSection\n' "$keymap" >/etc/X11/xorg.conf.d/00-keyboard.conf \
        2>>err.o || err=true
    # .local hostname resolution
    if pacman -Q nss-mdns &>/dev/null ; then
        grep -e "hosts:.*mdns_minimal" /etc/nsswitch.conf &>/dev/null || \
            sed -i '/^hosts:/s/\(resolve\|dns\)/mdns_minimal \[NOTFOUND=return\] \1/' /etc/nsswitch.conf \
            >/dev/null 2>>err.o || err=true
    fi
    if pacman -Q mlocate &>/dev/null ; then
        grep -e "PRUNENAMES.*\.snapshots" /etc/updatedb.conf &>/dev/null || \
            sed -i '/^PRUNENAMES/s/"\(.*\)"/"\1 .snapshots"/' /etc/updatedb.conf \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
}

# Adding user and setting password
archer_user() {
    printm 'Adding user and setting password'
    mkdir -p /etc/sudoers.d/
    chmod 750 /etc/sudoers.d/ \
        2>>err.o || err=true
    echo "root ALL=(ALL) ALL" > /etc/sudoers.d/root \
        2>>err.o || err=true
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel \
        2>>err.o || err=true
    # removed later
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheelnopasswd
    useradd -m -G wheel -s /bin/bash "$username" \
        >/dev/null 2>>err.o || err=true
    # Other groups
    if pacman -Q libvirt &>/dev/null ; then
        usermod -aG libvirt "$username" \
            >/dev/null 2>>err.o || err=true
    fi
    if pacman -Q wireshark-cli &>/dev/null ; then
        usermod -aG wireshark "$username" \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
    passwd "$username"
}

# Installing AUR helper and packages
archer_aurinstall() {
    if [ -n "$aurhelper" ] ; then
        aurcmd="$(echo "$aurhelper" | sed -r 's/-(bin|git)//g')"
        # Installing AUR helper
        printm "Installing AUR helper ($aurhelper)"
        pacman --noconfirm --needed -S base-devel git \
            >/dev/null 2>>err.o || err=true
        cd /tmp \
            >/dev/null 2>>err.o || err=true
        sudo -u "$username" git clone "https://aur.archlinux.org/$aurhelper.git" \
            >/dev/null 2>>err.o || err=true
        cd "$aurhelper" \
            >/dev/null 2>>err.o || err=true
        sudo -u "$username" makepkg --noconfirm -si \
            >/dev/null 2>>err.o || err=true
        showresult
        if [ -n "$aurpackages" ] ; then
            printm 'Installing AUR packages (Failures can be checked out manually later)'
            for aur in $aurpackages; do
                sudo -u "$username" "$aurcmd" -S --noconfirm "$aur" \
                    >/dev/null 2>>err.o || err=true
            done
            showresult
        fi
    fi
}

# Installing dotfiles from git repo
archer_dotfiles() {
    if [ ${#dotfilesrepo[@]} -gt 0 ] ; then
        printm 'Installing dotfiles from git repo'
        pacman --noconfirm --needed -S git \
            >/dev/null 2>>err.o || err=true
        for repo in "${dotfilesrepo[@]}" ; do
            tempdir=$(mktemp -d) \
                >/dev/null 2>>err.o || err=true
            chown -R "$username:$username" "$tempdir" \
                >/dev/null 2>>err.o || err=true
            sudo -u "$username" git clone --depth 1 "$repo" "$tempdir/dotfiles" \
                >/dev/null 2>>err.o || err=true
            rm -rf "$tempdir/dotfiles/.git"
            sudo -u "$username" cp -rfT "$tempdir/dotfiles" "/home/$username" \
                >/dev/null 2>>err.o || err=true
        done
        showresult
    fi
}

# Enabeling installed services
archer_services() {
    printm 'Enabeling services (Created symlink "errors" can be ignored)'
    # Services: network manager
    if pacman -Q networkmanager &>/dev/null ; then
        systemctl enable NetworkManager.service \
            >/dev/null 2>>err.o || err=true
        systemctl enable NetworkManager-wait-online.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q connman &>/dev/null ; then
        systemctl enable connman.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q wicd &>/dev/null ; then
        systemctl enable wicd.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q dhcpcd &>/dev/null ; then
        systemctl enable dhcpcd.service \
            >/dev/null 2>>err.o || err=true

    else
        eth="$(basename /sys/class/net/en*)"
        wifi="$(basename /sys/class/net/wl*)"
        [ -d "/sys/class/net/$eth" ] && \
            printf "[Match]\nName=%s\n\n[Network]\nDHCP=yes\n\n[DHCP]\nRouteMetric=10" "$eth" \
            > /etc/systemd/network/20-wired.network
        [ -d "/sys/class/net/$wifi" ] && \
            printf "[Match]\nName=%s\n\n[Network]\nDHCP=yes\n\n[DHCP]\nRouteMetric=20" "$wifi" \
            > /etc/systemd/network/25-wireless.network
        systemctl enable systemd-networkd.service \
            >/dev/null 2>>err.o || err=true
        systemctl enable systemd-networkd-wait-online.service \
            >/dev/null 2>>err.o || err=true
        systemctl enable systemd-resolved.service \
            >/dev/null 2>>err.o || err=true
        umount /etc/resolv.conf \
            2>/dev/null
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf \
            2>>err.o || err=true
    fi

    # Services: display manager
    if pacman -Q lightdm &>/dev/null ; then
        systemctl enable lightdm.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q lxdm &>/dev/null ; then
        systemctl enable lxdm.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q gdm &>/dev/null ; then
        systemctl enable gdm.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q sddm &>/dev/null ; then
        systemctl enable sddm.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Q xorg-xdm &>/dev/null ; then
        systemctl enable xdm.service \
            >/dev/null 2>>err.o || err=true

    elif pacman -Qs entrance &>/dev/null ; then
        systemctl enable entrance.service \
            >/dev/null 2>>err.o || err=true
    fi

    # Services: other
    if pacman -Q util-linux &>/dev/null ; then
        systemctl enable fstrim.timer \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q bluez &>/dev/null ; then
        systemctl enable bluetooth.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q modemmanager &>/dev/null ; then
        systemctl enable ModemManager.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q ufw &>/dev/null ; then
        systemctl enable ufw.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q libvirt &>/dev/null ; then
        systemctl enable libvirtd.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q avahi &>/dev/null ; then
        systemctl enable avahi-daemon.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q cups &>/dev/null ; then
        systemctl enable cups.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q autorandr &>/dev/null ; then
        systemctl enable autorandr.service \
            >/dev/null 2>>err.o || err=true
    fi

    if pacman -Q auto-cpufreq &>/dev/null ; then
        systemctl enable auto-cpufreq.service \
            >/dev/null 2>>err.o || err=true
    fi
    showresult
}



# Printing OK/ERROR
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
# Padding
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
    archer_pacstrap
    archer_pkgfetch
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

# vim: set ts=4 sw=4 tw=0 et :
