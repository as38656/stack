#!/bin/bash
# Install the built packages on a clean Debian system and check that they work.
#
# Runs as root in a fresh debian container (see `make smoke`):
#   /out               built packages, one directory per component, read-only
#   VPP_COMMIT         commit the vpp packages must be built from
#   ZEBRA_RS_COMMIT    commit the zebra-rs package must be built from
set -euo pipefail

: "${VPP_COMMIT:?}" "${ZEBRA_RS_COMMIT:?}"

PLUGIN_DIR=/usr/lib/x86_64-linux-gnu/vpp_plugins
VPP_CLI=/run/vpp/cli.sock

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

installed_version() {
	dpkg-query --showformat='${Version}' --show "$1"
}

install_all_packages() {
	export DEBIAN_FRONTEND=noninteractive
	# The vpp postinst would apply 80-vpp.conf, which asks for 1024 hugepages.
	export VPP_INSTALL_SKIP_SYSCTL=1

	apt-get update -qq
	apt-get install -y -qq --no-install-recommends dpkg-dev binutils >/dev/null

	mkdir -p /srv/repo
	cp /out/*/*.deb /srv/repo/
	(cd /srv/repo && dpkg-scanpackages --multiversion . >Packages 2>/dev/null)
	echo 'deb [trusted=yes] file:/srv/repo ./' >/etc/apt/sources.list.d/stack.list
	apt-get update -qq

	local packages
	packages=$(awk '/^Package:/ { print $2 }' /srv/repo/Packages | sort -u)
	# shellcheck disable=SC2086
	if ! apt-get install -y -qq $packages >/tmp/apt-install.log 2>&1; then
		cat /tmp/apt-install.log
		echo "FAIL: the packages install"
		exit 1
	fi
}

start_vpp() {
	mkdir -p /run/vpp
	# No hugepages in a container, so every memory pool uses 4k pages.
	cat >/tmp/startup.conf <<-EOF
		unix { nodaemon cli-listen $VPP_CLI log /tmp/vpp.log }
		memory { main-heap-size 256M main-heap-page-size 4k }
		buffers { buffers-per-numa 16384 page-size 4k }
		statseg { size 32M page-size 4k }
		plugins {
		  plugin dpdk_plugin.so { disable }
		  plugin linux_cp_plugin.so { enable }
		  plugin linux_nl_plugin.so { enable }
		}
	EOF
	vpp -c /tmp/startup.conf >/tmp/vpp.out 2>&1 &

	local _
	for _ in $(seq 60); do
		if vppctl -s "$VPP_CLI" show version >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.5
	done
	echo "vpp did not start:" >&2
	cat /tmp/vpp.out >&2
	return 1
}

vpp_package_matches_commit() {
	[[ $(installed_version vpp) == *"~g${VPP_COMMIT:0:7}"* ]]
}

zebra_rs_package_matches_commit() {
	[[ $(installed_version zebra-rs) == *"+as38656."*".g${ZEBRA_RS_COMMIT:0:12}" ]]
}

# Command output is captured before grep: with pipefail, `cmd | grep -q` fails
# when grep exits early and cmd gets SIGPIPE.
dpdk_has_sfc_driver() {
	local symbols
	symbols=$(strings "$PLUGIN_DIR/dpdk_plugin.so")
	grep -qx 'net_sfc_efx' <<<"$symbols"
}

vpp_reports_commit() {
	local version
	version=$(vppctl -s "$VPP_CLI" show version)
	grep -q "g${VPP_COMMIT:0:7}" <<<"$version"
}

vpp_loaded_linux_cp() {
	local plugins
	plugins=$(vppctl -s "$VPP_CLI" show plugins)
	grep -q linux_cp_plugin.so <<<"$plugins" && grep -q linux_nl_plugin.so <<<"$plugins"
}

zebra_rs_runs() {
	zebra-rs --version >/dev/null
}

install_all_packages

check "vpp package is built from $VPP_COMMIT" vpp_package_matches_commit
check "zebra-rs package is built from $ZEBRA_RS_COMMIT" zebra_rs_package_matches_commit
check "DPDK plugin includes the sfc driver" dpdk_has_sfc_driver
check "zebra-rs runs" zebra_rs_runs

if start_vpp; then
	check "running vpp reports the commit" vpp_reports_commit
	check "vpp loads linux-cp and linux-nl" vpp_loaded_linux_cp
else
	check "vpp starts" false
fi

if ((failures > 0)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
