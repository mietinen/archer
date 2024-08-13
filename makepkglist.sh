#!/usr/bin/env bash
#
# Makes a list of installed groups and packages, with description
# Example:
#   list installed packages:
#       $ ./makepkglist.sh
#   list installed packages which is not listed in pkglist.txt
#       $ ./makepkglist.sh pkglist.txt [pkglist2.txt ..]
#   to save the list, redirect the output to a file
#       $ ./makepkglist.sh > pkglist.txt
#
## Copyright (c) 2022 Aleksander Mietinen

[ -n "$1" ] && list="$(cat "$@" | grep -oE '^[^(#|[:space:])]*' | sort -u)"

echo "# Generated with makepkglist.sh"
echo "# - https://github.com/mietinen/archer"
echo
for p in $(comm -23 <(pacman -Qqe | sort -u) <(echo "$list")); do
    desc="$(pacman -Qi "$p" | grep Description | cut -d: -f2)"
    pacman -Qm "$p" >/dev/null 2>&1 && aur=" (AUR)" || aur=""
    printf "%-32s%s\n" "$p" "#$desc$aur"
done
