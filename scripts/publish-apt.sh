#!/bin/bash
# Add packages to the flat APT repository kept in the release apt-<suite>.
#
#   scripts/publish-apt.sh DEB...
#
# Environment:
#   GH_REPO             repository that holds the release, e.g. as38656/stack
#   GH_TOKEN            token with contents: write on GH_REPO
#   APT_SUITE           Debian suite of the packages, e.g. trixie
#   APT_KEEP            versions kept for each package and architecture
#   APT_GPG_KEY_ID      signing key, already imported into gpg
#   APT_GPG_PASSPHRASE  passphrase of the signing key
#
# Published versions are never replaced. A package whose version is already
# in the repository is skipped.
set -euo pipefail

: "${GH_REPO:?}" "${GH_TOKEN:?}" "${APT_SUITE:?}" "${APT_KEEP:?}" "${APT_GPG_KEY_ID:?}"
: "${APT_GPG_PASSPHRASE?}"
if (($# == 0)); then
	echo "usage: $0 DEB..." >&2
	exit 2
fi

stack=$(cd "$(dirname "$0")/.." && pwd)
tag=apt-$APT_SUITE
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/incoming" "$work/current" "$work/repo"

aptrepo() {
	PYTHONPATH=$stack python3 -m aptrepo "$@"
}

sign() {
	gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
		--local-user "$APT_GPG_KEY_ID" "$@" 3<<<"$APT_GPG_PASSPHRASE"
}

# Name the files as GitHub will name the assets, so that the Filename fields
# in Packages point to the uploaded assets.
for deb in "$@"; do
	cp "$deb" "$work/incoming/$(aptrepo asset-name "$deb")"
done
(cd "$work/incoming" && dpkg-scanpackages --multiversion . >../incoming.Packages)

if gh release view "$tag" >/dev/null 2>&1; then
	gh release download "$tag" --pattern Packages --dir "$work/current"
	release_exists=true
else
	: >"$work/current/Packages"
	release_exists=false
fi

aptrepo update \
	--current "$work/current/Packages" \
	--incoming "$work/incoming.Packages" \
	--keep "$APT_KEEP" \
	--packages "$work/repo/Packages" \
	--upload "$work/upload" \
	--remove "$work/remove"

(
	cd "$work/repo"
	gzip -9 -k Packages
	apt-ftparchive \
		-o APT::FTPArchive::Release::Origin=as38656 \
		-o APT::FTPArchive::Release::Label=as38656 \
		-o APT::FTPArchive::Release::Suite="$APT_SUITE" \
		-o APT::FTPArchive::Release::Codename="$APT_SUITE" \
		-o APT::FTPArchive::Release::Architectures=amd64 \
		release . >"$work/Release"
	mv "$work/Release" Release
	sign --armor --detach-sign --output Release.gpg Release
	sign --clearsign --output InRelease Release
)

if ! $release_exists; then
	gh release create "$tag" --latest=false \
		--title "APT repository ($APT_SUITE)" \
		--notes "Flat APT repository for Debian $APT_SUITE, updated by the release workflow. Do not delete."
fi

# Upload the packages before the index that refers to them, and delete old
# packages only after the index no longer refers to them.
mapfile -t uploads <"$work/upload"
if ((${#uploads[@]} > 0)); then
	gh release upload "$tag" --clobber "${uploads[@]/#/$work/incoming/}"
fi
gh release upload "$tag" --clobber \
	"$work/repo/Packages" "$work/repo/Packages.gz" \
	"$work/repo/Release" "$work/repo/Release.gpg" "$work/repo/InRelease"
while read -r asset; do
	gh release delete-asset "$tag" "$asset" --yes
done <"$work/remove"

echo "uploaded ${#uploads[@]} package(s), removed $(wc -l <"$work/remove") old package(s)"
