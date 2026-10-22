#!/bin/bash
# Build the zebra-rs Debian package from the zebra-rs submodule.

# shellcheck source=build/lib.sh
source "$(dirname "$0")/lib.sh"

# Same version as upstream's build-debs.yaml. The asset layout rules of
# cargo-deb change between versions.
CARGO_DEB_VERSION=3.7.0

export CARGO_HOME=/cache/cargo
export RUSTUP_HOME=/cache/rustup
export PATH=$CARGO_HOME/bin:$PATH
# Download cache of the bash sources that vty patches.
export CACHE_DIR=/cache/zebra-rs

checkout zebra-rs
cd /work/zebra-rs

apt-get update
apt-get install -y --no-install-recommends bison libpam0g-dev pkg-config protobuf-compiler xxd

if ! command -v rustup >/dev/null; then
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
		sh -s -- -y --no-modify-path --profile minimal --default-toolchain none
fi
rustup toolchain install stable --profile minimal
rustup default stable
cargo install cargo-deb --version "$CARGO_DEB_VERSION" --locked

# <upstream version>+as38656.<commit count>.g<commit>: sorts after the upstream
# release it is based on, and grows with each commit on our branch.
commit=$(git rev-parse HEAD)
version="$(cat version)+as38656.$(git rev-list --count HEAD).g${commit:0:12}"

DEB_VERSION=$version make -C packaging amd64

publish zebra-rs packaging/zebra-rs_*_amd64.deb
