#!/bin/bash
# Build the vpp-plugin-etherip Debian package from the vpp-etherip submodule,
# against the vpp packages in /out/vpp (see `make vpp`).

# shellcheck source=build/lib.sh
source "$(dirname "$0")/lib.sh"

vpp_debs=(/out/vpp/libvppinfra_*.deb /out/vpp/libvppinfra-dev_*.deb /out/vpp/vpp_*.deb /out/vpp/vpp-dev_*.deb)
for deb in "${vpp_debs[@]}"; do
	if [[ ! -f $deb ]]; then
		echo "$deb is missing: build vpp first" >&2
		exit 1
	fi
done

checkout vpp-etherip
cd /work/vpp-etherip

apt-get update
apt-get install -y --no-install-recommends clang cmake ninja-build python3-ply
VPP_INSTALL_SKIP_SYSCTL=1 apt-get install -y "${vpp_debs[@]}"

vpp_version=$(dpkg-query --showformat='${Version}' --show vpp)
api_version=$(sed -n 's/^option version = "\(.*\)";$/\1/p' etherip/etherip.api)
commit=$(git rev-parse HEAD)
# <API version>+as38656.<commit count>.g<commit>+vpp<vpp version>: grows with
# each commit, and changes when the same commit is built against another vpp.
version="${api_version}+as38656.$(git rev-list --count HEAD).g${commit:0:12}+vpp${vpp_version//[-~]/.}"

cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
DESTDIR=/work/pkg cmake --install build
# The headers are for API clients; routers need only the plugins and the API definition.
rm -rf /work/pkg/usr/include

mkdir -p /work/pkg/DEBIAN
cat >/work/pkg/DEBIAN/control <<EOF
Package: vpp-plugin-etherip
Version: $version
Architecture: amd64
Maintainer: AS38656 <github@loutres.me>
Depends: vpp (= $vpp_version)
Section: net
Priority: optional
Homepage: https://github.com/as38656/vpp-etherip
Description: EtherIP (RFC 3378) tunnel plugin for VPP
 Built from commit $commit against vpp $vpp_version.
EOF

dpkg-deb --root-owner-group --build /work/pkg "/work/vpp-plugin-etherip_${version}_amd64.deb"
dpkg-deb --contents /work/vpp-plugin-etherip_*.deb

publish vpp-etherip /work/vpp-plugin-etherip_*_amd64.deb
