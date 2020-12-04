#!/usr/bin/env bash
# makepkglist.sh
# Makes a list of installed groups and packages, with description
# Usage: bash makepkglist.sh > pkglist.txt

pacs="$(pacman -Qq | sort)"
excl="$(pacman -Qqe | sort)"

echo "# pkglist.txt - package list"
echo
echo "# Groups:"
for g in $(pacman -Qqg | awk '{print $1}' | uniq -c | sort -r | awk '{print $2}'); do
	sqg="$(pacman -Sqg "$g" | sort)"
	count="$(echo "$sqg" | wc -l)"
	matches="$(comm -12 <(echo "$pacs") <(echo "$sqg") | wc -l)"
	if [ $count -eq $matches ] ; then
		pacs="$(comm -23 <(echo "$pacs") <(echo "$sqg"))"
		groups="$groups $g"
		printf "%-32s%s\n" "$g" "# Group: $g"
	fi
done

echo
echo "# Other packages:" 
gpacs="$(pacman -Sgq $groups | sort)"
for p in $(comm -23 <(echo "$excl") <(echo "$gpacs")); do
	desc="$(pacman -Qi "$p" | grep Description | cut -d: -f2)"
	printf "%-32s%s\n" "$p" "#$desc"
done
	
