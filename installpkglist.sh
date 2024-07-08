#!/usr/bin/env bash

# Install packages from a list.
# Usage:
#   $ ./installpkglist.sh <pkglist.txt>
#
## Copyright (c) 2022 Aleksander Mietinen
aurcmd="paru"

if [ ! -r "$1" ]; then
    echo "Usage ${0##*/} <pkglist.txt>"
    exit 1
fi

list="$(grep -oE '^[^(#|[:space:])]*' "$1" | sort -u)"
new=$(comm -13 <(pacman -Qq | sort -u) <(echo "$list"))
repo="$(cat <(pacman -Slq) <(pacman -Sgq) | sort -u)"
packages=$(comm -12 <(echo "$repo") <(echo "$new") | tr '\n' ' ')
aurpackages=$(comm -13 <(echo "$repo") <(echo "$new") | tr '\n' ' ')

echo "Packages to install:"
echo "$packages"
echo
echo "AUR packages to install:"
echo "$aurpackages"
echo

read -rep "Install all packages? [y/N] " install
[ "$install" != "${install#[Yy]}" ] || exit 0

pacman --noconfirm --needed --ask 4 -S $packages
for aur in $aurpackages; do
    "$aurcmd" -S --noconfirm "$aur"
done
