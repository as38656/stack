#!/bin/bash
# Build the VPP Debian packages from the vpp submodule.

# shellcheck source=build/lib.sh
source "$(dirname "$0")/lib.sh"

checkout vpp
cd /work/vpp

apt-get update
make UNATTENDED=y install-dep

# vpp-ext-deps holds DPDK and the other external libraries and takes most of
# the build time. Reuse the package built from the same build/external tree.
ext_deps_cache=/cache/vpp-ext-deps/$(git rev-parse HEAD:build/external)
if compgen -G "$ext_deps_cache/*.deb" >/dev/null; then
	apt-get install -y "$ext_deps_cache"/*.deb
fi
make UNATTENDED=y install-ext-deps
if compgen -G "build/external/vpp-ext-deps_*.deb" >/dev/null; then
	rm -rf "$ext_deps_cache"
	mkdir -p "$ext_deps_cache"
	cp build/external/vpp-ext-deps_*.deb "$ext_deps_cache/"
fi

make UNATTENDED=y pkg-deb

publish vpp build-root/*.deb
