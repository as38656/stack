#!/bin/bash
# Print the commit checked out in a component submodule.
#
#   scripts/component-commit.sh vpp
#
# Fails when the submodule is not initialized. `git -C vpp rev-parse HEAD`
# would instead print the commit of this repository.
set -euo pipefail

component=${1:?usage: $0 COMPONENT}
status=$(git -C "$(dirname "$0")/.." submodule status -- "$component")
if [[ -z $status ]]; then
	echo "$component is not a submodule" >&2
	exit 1
fi
if [[ $status == -* ]]; then
	echo "submodule $component is not initialized" >&2
	exit 1
fi
echo "${status:1:40}"
