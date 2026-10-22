#!/bin/bash
# Print the notes of a stack release: the component commits and the packages
# built from them.
#
#   scripts/release-notes.sh DEB...
set -euo pipefail

stack=$(cd "$(dirname "$0")/.." && pwd)

echo "## Components"
echo
echo "| Component | Commit |"
echo "|---|---|"
for component in vpp zebra-rs; do
	commit=$("$stack/scripts/component-commit.sh" "$component")
	url=$(git -C "$stack" config --file .gitmodules "submodule.$component.url")
	echo "| $component | [\`${commit:0:12}\`](${url%.git}/commit/$commit) |"
done

echo
echo "## Packages"
echo
echo "| Package | Version |"
echo "|---|---|"
for deb in "$@"; do
	echo "| $(dpkg-deb --field "$deb" Package) | \`$(dpkg-deb --field "$deb" Version)\` |"
done | sort
