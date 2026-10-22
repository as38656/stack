#!/bin/bash
# Publish packages with scripts/publish-apt.sh into a fake GitHub release and
# check that apt accepts the result.
#
# Runs as root in a fresh debian container (see `make apt-test`):
#   /stack   this repository, read-only
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends apt-utils dpkg-dev gnupg python3 >/dev/null

work=$(mktemp -d)
# apt reads the repository as the _apt user.
chmod 755 "$work"
export PATH=/stack/test/fake-gh:$PATH
export FAKE_GH_ROOT=$work/releases
export GNUPGHOME=$work/gnupg
export GH_REPO=as38656/stack GH_TOKEN=unused
export APT_SUITE=trixie APT_KEEP=2 APT_GPG_PASSPHRASE=''
mkdir -p "$FAKE_GH_ROOT" "$work/debs"
mkdir -m 700 "$GNUPGHOME"

gpg --batch --quiet --passphrase '' --quick-generate-key 'stack test' ed25519 sign never
APT_GPG_KEY_ID=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
export APT_GPG_KEY_ID
mkdir -p /etc/apt/keyrings
gpg --export "$APT_GPG_KEY_ID" >/etc/apt/keyrings/stack.gpg

repo=$FAKE_GH_ROOT/apt-trixie
failures=0

check() {
	local name=$1
	shift
	if "$@"; then
		echo "ok: $name"
	else
		echo "FAIL: $name"
		failures=$((failures + 1))
	fi
}

# Build an empty package and print its path.
make_deb() {
	local name=$1 version=$2 root
	root=$(mktemp -d)
	mkdir "$root/DEBIAN"
	cat >"$root/DEBIAN/control" <<-EOF
		Package: $name
		Version: $version
		Architecture: amd64
		Maintainer: stack test <test@example.invalid>
		Description: test package
	EOF
	echo "$name $version $RANDOM" >"$root/DEBIAN/random"
	dpkg-deb --root-owner-group --build "$root" "$work/debs/${name}_${version}_amd64.deb" >/dev/null
	echo "$work/debs/${name}_${version}_amd64.deb"
}

publish() {
	/stack/scripts/publish-apt.sh "$@" >/dev/null
}

publish "$(make_deb demo 1.0~rc1)" "$(make_deb other 1.0)"
first_other_sha=$(sha256sum <"$repo/other_1.0_amd64.deb")
publish "$(make_deb demo 1.0)"
publish "$(make_deb demo 1.1)" "$(make_deb other 1.0)"

check "the oldest demo version is removed" test ! -e "$repo/demo_1.0.rc1_amd64.deb"
check "the two newest demo versions are kept" \
	test -f "$repo/demo_1.0_amd64.deb" -a -f "$repo/demo_1.1_amd64.deb"
check "a published version is not replaced" \
	test "$(sha256sum <"$repo/other_1.0_amd64.deb")" = "$first_other_sha"

echo "deb [signed-by=/etc/apt/keyrings/stack.gpg] file:$repo ./" >/etc/apt/sources.list.d/stack.list
check "apt accepts the signed repository" apt-get update -qq -o APT::Update::Error-Mode=any
check "apt sees the kept demo versions" \
	test "$(apt-cache madison demo | awk '{ print $3 }' | xargs)" = "1.1 1.0"
check "the packages install" apt-get install -y -qq demo other

if ((failures > 0)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
