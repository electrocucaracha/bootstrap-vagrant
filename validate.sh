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
}

function warn {
    _print_msg "WARN" "$1"
}

function error {
    _print_msg "ERROR" "$1"
    exit 1
}

function _print_msg {
    msg+="$(date +%H:%M:%S) - $1: $2\n"
}

function print_summary {
    echo -e "$msg"
}

msg="Summary:\n\n"
trap print_summary ERR

if ! command -v vagrant > /dev/null; then
    error "Vagrant command line wasn't installed"
fi

if [[ "$(vagrant version | awk 'NR==1{print $3}')" != "2.2.19" ]]; then
    warn "Vagrant command line has different version"
fi

if command -v VBoxManage > /dev/null; then
    info "VirtualBox command line was installed"
    sudo systemctl restart vboxdrv
    VAGRANT_DEFAULT_PROVIDER=virtualbox
elif command -v virsh > /dev/null; then
    VAGRANT_DEFAULT_PROVIDER=libvirt
    info "Libvirt command line was installed"
    qemu_validate=$(sudo virt-host-validate qemu || :)
    # shellcheck disable=SC2001
    iommu_support=$(echo "$qemu_validate" | sed "s|.*Checking for device assignment IOMMU support||")
    if [[ "$iommu_support" != *PASS* ]]; then
        info "QEMU doesn't support IOMMU,$(awk -F':' '{print $2}' <<< "$iommu_support")"
    fi

    info "Validating QEMU image tool"
    if ! command -v qemu-img; then
        error "qemu-img command line tool wasn't installed"
    fi

    info "Validating Nested Virtualization"
    vendor_id=$(lscpu|grep "Vendor ID")
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

if [ -f /etc/init.d/qat_service ]; then
    info "Validating Intel QuickAssist drivers installation"
    if ! sudo /etc/init.d/qat_service status | grep "There is .* QAT acceleration device(s) in the system:" > /dev/null; then
        error "QAT drivers and/or service weren't installed properly"
    else
        if [[ -z "$(for i in 0442 0443 37c9 19e3; do lspci -d 8086:$i; done)" ]]; then
            warn "There are no Virtual Functions enabled for any QAT device"
        fi
    fi
fi

info "Validating Vagrant operation"
pushd "$(mktemp -d)"
cat << EOT > vagrant_file.erb
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
vagrant init generic/alpine313 --box-version 3.5.0 --template vagrant_file.erb
# shellcheck disable=SC1091
source /etc/os-release || source /usr/lib/os-release
if [[ "${ID,,}" == "ubuntu" ]]; then
    sudo -E vagrant up
    sudo -E vagrant halt
    sudo -E vagrant package
    if [ ! -f package.box ]; then
        error "Vagrant couldn't package the running box"
    fi
    sudo -E vagrant destroy -f
else
    vagrant status
    warn "There are some unsolved vagrant-libvirt issues with this distro"
fi
popd

trap ERR
print_summary
