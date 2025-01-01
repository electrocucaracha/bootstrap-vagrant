#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2019
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o nounset
set -o pipefail
set -o errexit

function info {
    _print_msg "INFO" "$1"
    echo "::notice::$1"
}

function warn {
    _print_msg "WARN" "$1"
    echo "::warning::$1"
}

function error {
    _print_msg "ERROR" "$1"
    exit 1
}

function _print_msg {
    echo "$(date +%H:%M:%S) - $1: $2"
}

function _exit_trap {
    if [ -f /proc/stat ]; then
        printf "CPU usage: "
        grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage " %"}'
    fi
    if [ -f /proc/pressure/io ]; then
        printf "I/O Pressure Stall Information (PSI): "
        grep full /proc/pressure/io | awk '{ sub(/avg300=/, ""); print $4 }'
    fi
    printf "Memory free(Kb):"
    if [ -f /proc/zoneinfo ]; then
        awk -v low="$(grep low /proc/zoneinfo | awk '{k+=$2}END{print k}')" '{a[$1]=$2}  END{ print a["MemFree:"]+a["Active(file):"]+a["Inactive(file):"]+a["SReclaimable:"]-(12*low);}' /proc/meminfo
    fi
    if command -v vm_stat; then
        vm_stat | awk '/Pages free/ {print $3 * 4 }'
    fi
    ! command -v VBoxManage >/dev/null || VBoxManage list runningvms --long
    ! command -v virsh >/dev/null || virsh list
}

trap _exit_trap ERR

if ! command -v vagrant >/dev/null; then
    error "Vagrant command line wasn't installed"
fi

if [[ "$(vagrant version | awk 'NR==1{print $3}')" != "2.4.1" ]]; then
    warn "Vagrant command line has different version"
fi

if command -v VBoxManage >/dev/null; then
    info "VirtualBox command line was installed"
    sudo systemctl restart vboxdrv
    VAGRANT_DEFAULT_PROVIDER=virtualbox
elif command -v virsh >/dev/null; then
    VAGRANT_DEFAULT_PROVIDER=libvirt
    info "Libvirt command line was installed"
    qemu_validate=$(sudo virt-host-validate qemu || :)
    # shellcheck disable=SC2001
    iommu_support=$(echo "$qemu_validate" | sed "s|.*Checking for device assignment IOMMU support||")
    if [[ $iommu_support != *PASS* ]]; then
        info "QEMU doesn't support IOMMU,$(awk -F':' '{print $2}' <<<"$iommu_support")"
    fi

    info "Validating QEMU image tool"
    if ! command -v qemu-img; then
        error "qemu-img command line tool wasn't installed"
    fi

    info "Validating Nested Virtualization"
    vendor_id=$(lscpu | grep "Vendor ID")
    if [[ $vendor_id == *GenuineIntel* ]]; then
        kvm_ok=$(cat /sys/module/kvm_intel/parameters/nested)
        if [[ $kvm_ok == 'N' ]]; then
            error "Nested-Virtualization wasn't enabled for this Intel processor"
        fi
    else
        kvm_ok=$(cat /sys/module/kvm_amd/parameters/nested)
        if [[ $kvm_ok == '0' ]]; then
            error "Nested-Virtualization wasn't enabled for this processor"
        fi
    fi
else
    error "VirtualBox/Libvirt command line wasn't installed"
fi
export VAGRANT_DEFAULT_PROVIDER
info "Get vagrant plugin list"
vagrant plugin list

info "Validating Vagrant operation"
pushd "$(mktemp -d)"
# editorconfig-checker-disable
cat <<EOT >vagrant_file.erb
Vagrant.configure("2") do |config|
  config.vm.box = "<%= box_name %>"

  [:virtualbox, :libvirt].each do |provider|
  config.vm.provider provider do |p|
      p.cpus = 2
      p.memory = 1024
    end
  end
end
EOT
# editorconfig-checker-enable
vagrant init generic/alpine316 --box-version 3.5.0 --template vagrant_file.erb
if vagrant up >/dev/null; then
    vagrant halt
    vagrant package
    if [ ! -f package.box ]; then
        warn "Vagrant couldn't package the running box"
    fi
    vagrant destroy -f
else
    error "Vagrant couldn't run the box"
fi
popd
