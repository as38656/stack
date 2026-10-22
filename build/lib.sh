# shellcheck shell=bash
# Shared steps of the component build scripts.
#
# The scripts run as root in the builder container (see `make vpp`):
#   /stack              this repository, read-only
#   /out                output; each component replaces /out/<component>/
#   /cache              cache kept between builds
#   HOST_UID, HOST_GID  owner of the files written to /out and /cache

set -euo pipefail

: "${HOST_UID:?}" "${HOST_GID:?}"

trap 'chown -R "$HOST_UID:$HOST_GID" /out /cache' EXIT

# Clone the commit checked out in the submodule to /work/<component>, so the
# build never writes into /stack. --shared reads the objects straight from the
# submodule, so the commit is found even when no branch points to it.
checkout() {
	local component=$1 commit
	commit=$(/stack/scripts/component-commit.sh "$component")
	git clone --quiet --shared --no-checkout "/stack/$component" "/work/$component"
	git -C "/work/$component" checkout --quiet --detach "$commit"
}

publish() {
	local component=$1
	shift
	rm -rf "/out/${component:?}"
	mkdir -p "/out/$component"
	cp "$@" "/out/$component/"
	ls -l "/out/$component"
}
