#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2021
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o errexit
set -o pipefail
if [[ ${DEBUG:-false} == "true" ]]; then
    set -o xtrace
fi

eval "$(curl -fsSL https://raw.githubusercontent.com/electrocucaracha/pkg-mgr_scripts/master/ci/pinned_versions.env)"

sed -i "s|PKG_VAGRANT_VERSION:-.*|PKG_VAGRANT_VERSION:-$PKG_VAGRANT_VERSION}|g" setup.sh
sed -i "s/vagrant version.*/vagrant version | awk 'NR==1\{print \$3}')\" != \"$PKG_VAGRANT_VERSION\" \]\]; then/g" validate.sh

# Update GitHub Action commit hashes
gh_actions=$(grep -r "uses: [a-z\-]*/[\_a-z\-]*@" .github/workflows/ | sed 's/@.*//' | awk -F ': ' '{ print $3 }' | sort | uniq)
for action in $gh_actions; do
    commit_hash=$(git ls-remote --tags "https://github.com/$action" | grep 'refs/tags/[v]\?[0-9][0-9\.]*$' | awk '{ print $NF,$0 }' | sort -k1,1 -V | cut -f2- -d' ' | grep -oh '.*refs/tags/[v0-9\.]*$' | tail -1 | awk '{ printf "%s # %s\n",$1,$2 }')
    # shellcheck disable=SC2267
    grep -ElRZ "uses: $action@" .github/workflows/ | xargs -0 -l sed -i -e "s|uses: $action@.*|uses: $action@$commit_hash|g"
done
