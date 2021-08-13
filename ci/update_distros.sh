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
if [[ "${KRD_DEBUG:-false}" == "true" ]]; then
    set -o xtrace
fi

PROVIDER=${KRD_PROVIDER:-virtualbox}
msg=""

function _get_box_current_version {
    version=""
    attempt_counter=0
    max_attempts=5

    until [ "$version" ]; do
        tags="$(curl -s "https://app.vagrantup.com/api/v1/box/$1")"
        if [ "$tags" ]; then
            version="$(echo "$tags" | python -c 'import json,sys;print(json.load(sys.stdin)["current_version"]["version"])')"
            break
        elif [ ${attempt_counter} -eq ${max_attempts} ];then
            echo "Max attempts reached"
            exit 1
        fi
        attempt_counter=$((attempt_counter+1))
        sleep $((attempt_counter*2))
    done

    echo "${version#*v}"
}

function _vagrant_pull {
    local alias="$1"
    local name="$2"

    version=$(_get_box_current_version "$name")

    if [ "$(curl "https://app.vagrantup.com/${name%/*}/boxes/${name#*/}/versions/$version/providers/$PROVIDER.box" -o /dev/null -w '%{http_code}\n' -s)" == "302" ] && [ "$(vagrant box list | grep -c "$name .*$PROVIDER, $version")" != "1" ]; then
        vagrant box remove --provider "$PROVIDER" --all --force "$name" ||:
        vagrant box add --provider "$PROVIDER" --box-version "$version" "$name"
    elif [ "$(vagrant box list | grep -c "$name .*$PROVIDER, $version")" == "1" ]; then
        echo "$name($version, $PROVIDER) box is already present in the host"
    else
        msg+="$name($version, $PROVIDER) box doesn't exist\n"
        return
    fi
    cat << EOT >> .distros_supported.yml
  - alias: $alias
    name: $name
    version: $version
EOT
}

if ! command -v vagrant > /dev/null; then
    # NOTE: Shorten link -> https://github.com/electrocucaracha/bootstrap-vagrant
    curl -fsSL http://bit.ly/initVagrant | bash
fi

cat << EOT > .distros_supported.yml
---
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2019
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################
linux:
EOT

_vagrant_pull "centos_7" "centos/7"
_vagrant_pull "centos_8" "centos/8"
_vagrant_pull "ubuntu_bionic" "generic/ubuntu1804"
_vagrant_pull "ubuntu_focal" "generic/ubuntu2004"
_vagrant_pull "opensuse_tumbleweed" "opensuse/Tumbleweed.x86_64"
_vagrant_pull "opensuse_leap" "opensuse/Leap-15.2.x86_64"

if [ "$msg" ]; then
    echo -e "$msg"
    rm .distros_supported.yml
else
    mv .distros_supported.yml distros_supported.yml
fi
