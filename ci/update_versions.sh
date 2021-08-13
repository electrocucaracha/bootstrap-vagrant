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
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -o xtrace
fi

eval "$(curl -fsSL https://raw.githubusercontent.com/electrocucaracha/pkg-mgr_scripts/master/pinned_versions.env)"

sed -i "s|PKG_VAGRANT_VERSION:-.*|PKG_VAGRANT_VERSION:-$PKG_VAGRANT_VERSION}|g" setup.sh
sed -i "s/vagrant version.*/vagrant version | awk 'NR==1\{print \$3}')\" != \"$PKG_VAGRANT_VERSION\" \]\]; then/g" validate.sh
