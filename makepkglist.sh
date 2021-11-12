#!/usr/bin/env bash
# makepkglist.sh
# Makes a list of installed groups and packages, with description
# Usage: bash makepkglist.sh > pkglist.txt

pacs="$(pacman -Qq | sort)"
expl="$(pacman -Qqe | sort)"

echo "# pkglist.txt - package list"
echo
echo "# Groups:"
for g in $(pacman -Qqg | awk '{print $1}' | uniq); do
    sqg="$(pacman -Sqg "$g" | sort)"
    count="$(echo "$sqg" | wc -l)"
    matches="$(comm -12 <(echo "$pacs") <(echo "$sqg") | wc -l)"
    if [ $count -eq $matches ] ; then
        pacs="$(comm -23 <(echo "$pacs") <(echo "$sqg"))"
        groups="$groups $g"
        printf "%-32s%s\n" "$g" "# Group: $g"
    fi
done

gpacs="$(pacman -Sgq $groups | sort)"

echo
echo "# Other packages:"
for p in $(comm -23 <(echo "$expl") <(echo "$gpacs")); do
    desc="$(pacman -Qi "$p" | grep Description | cut -d: -f2)"
    pacman -Qm "$p" >/dev/null 2>&1 && aur=" (AUR)" || aur=""
    printf "%-32s%s\n" "$p" "#$desc$aur"
done

# vim: set ts=4 sw=4 tw=0 et :
