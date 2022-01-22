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

pacs="$(pacman -Qq | sort -u)"
[ -n "$1" ] && list="$(cat "$@" | grep -oE '^[^(#|[:space:])]*' | sort -u)"
expl="$(comm -23 <(pacman -Qqe | sort -u) <(echo "$list"))"

echo "# Generated with makepkglist.sh"
echo "# - https://github.com/mietinen/archer"
echo
echo "# Groups:"
for g in $(pacman -Qqg | awk '{print $1}' | sort -u); do
    sqg="$(pacman -Sqg "$g" | sort -u)"
    count="$(echo "$sqg" | wc -l)"
    matches="$(comm -12 <(echo "$pacs") <(echo "$sqg") | wc -l)"
    if [ $count -eq $matches ] ; then
        pacs="$(comm -23 <(echo "$pacs") <(echo "$sqg"))"
        groups="$groups $g"
        echo "$list" | grep -q "$g" || printf "%-32s%s\n" "$g" "# Group: $g"
    fi
done

gpacs="$(pacman -Sgq $groups | sort -u)"

echo
echo "# Other packages:"
for p in $(comm -23 <(echo "$expl") <(echo "$gpacs")); do
    desc="$(pacman -Qi "$p" | grep Description | cut -d: -f2)"
    pacman -Qm "$p" >/dev/null 2>&1 && aur=" (AUR)" || aur=""
    printf "%-32s%s\n" "$p" "#$desc$aur"
done

# vim: set ts=4 sw=4 tw=0 et :
