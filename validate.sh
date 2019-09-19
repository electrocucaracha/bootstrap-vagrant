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

if ! command -v vagrant; then
    echo "ERROR: Vagrant command line wasn't installed"
fi

if [[ "$(vagrant version | awk 'NR==1{print $3}')" != "2.2.5" ]]; then
    echo "ERROR: Vagrant command line has different version"
fi

if command -v VBoxManage; then
    echo "INFO: VirtualBox command line was installed"
elif command -v virsh; then
    echo "INFO: Libvirt command line was installed"
    iommu_support=$(sudo virt-host-validate qemu | grep 'Checking for device assignment IOMMU support')
    if [[ "$iommu_support" != *PASS* ]]; then
        awk -F':' '{print $3}' <<< "$iommu_support"
    fi
else
    echo "ERROR: VirtualBox/Libvirt command line wasn't installed"
fi

vendor_id=$(lscpu|grep "Vendor ID")
if [[ $vendor_id == *GenuineIntel* ]]; then
    kvm_ok=$(cat /sys/module/kvm_intel/parameters/nested)
    if [[ $kvm_ok == 'N' ]]; then
        echo "ERROR: Nested-Virtualization wasn't enabled for this Intel processor"
    fi
else
    kvm_ok=$(cat /sys/module/kvm_amd/parameters/nested)
    if [[ $kvm_ok == '0' ]]; then
        echo "ERROR: Nested-Virtualization wasn't enabled for this processor"
    fi
fi
