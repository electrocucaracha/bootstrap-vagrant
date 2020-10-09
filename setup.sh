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
set -o errexit
set -o pipefail

msg="Summary \n"
export PKG_VAGRANT_VERSION=2.2.10
export PKG_VIRTUALBOX_VERSION=6.1
export PKG_QAT_DRIVER_VERSION=1.7.l.4.11.0-00001
export PKG_QEMU_VERSION=5.1.0
if [ "${DEBUG:-false}" == "true" ]; then
    set -o xtrace
    export PKG_DEBUG=true
fi

function _reload_grub {
    if command -v clr-boot-manager; then
        sudo clr-boot-manager update
    elif command -v grub-mkconfig; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        sudo update-grub
    elif command -v grub2-mkconfig; then
        grub_cfg="$(sudo readlink -f /etc/grub2.cfg)"
        if dmesg | grep EFI; then
            grub_cfg="/boot/efi/EFI/centos/grub.cfg"
        fi
        sudo grub2-mkconfig -o "$grub_cfg"
    fi
}

function enable_iommu {
    if ! iommu_support=$(sudo virt-host-validate qemu | grep 'Checking for device assignment IOMMU support'); then
        echo "- WARN - IOMMU support checker reported: $(awk -F':' '{print $3}' <<< "$iommu_support")"
    fi
    if sudo virt-host-validate qemu | grep 'Checking if IOMMU is enabled by kernel'; then
        return
    fi
    if [[ "${ID,,}" == *clear-linux-os* ]]; then
        mkdir -p /etc/kernel/cmdline.d
        echo "intel_iommu=on" | sudo tee /etc/kernel/cmdline.d/enable-iommu.conf
    else
        if [ -f /etc/default/grub ]  && [[ "$(grep GRUB_CMDLINE_LINUX /etc/default/grub)" != *intel_iommu=on* ]]; then
            sudo sed -i "s|^GRUB_CMDLINE_LINUX\(.*\)\"|GRUB_CMDLINE_LINUX\1 intel_iommu=on\"|g" /etc/default/grub
        fi
    fi
    _reload_grub
    msg+="- WARN: IOMMU was enabled and requires to reboot the server to take effect\n"
}

function enable_nested_virtualization {
    vendor_id=$(lscpu|grep "Vendor ID")
    if [[ $vendor_id == *GenuineIntel* ]]; then
        if [ -f /sys/module/kvm_intel/parameters/nested ]; then
            kvm_ok=$(cat /sys/module/kvm_intel/parameters/nested)
            if [[ $kvm_ok == 'N' ]]; then
                msg+="- INFO: Intel Nested-Virtualization was enabled\n"
                sudo rmmod kvm-intel
                echo 'options kvm-intel nested=y' | sudo tee --append /etc/modprobe.d/dist.conf
                sudo modprobe kvm-intel
            fi
        fi
    else
        if [ -f /sys/module/kvm_amd/parameters/nested ]; then
            kvm_ok=$(cat /sys/module/kvm_amd/parameters/nested)
            if [[ $kvm_ok == '0' ]]; then
                msg+="- INFO: AMD Nested-Virtualization was enabled\n"
                sudo rmmod kvm-amd
                echo 'options kvm-amd nested=1' | sudo tee --append /etc/modprobe.d/dist.conf
                sudo modprobe kvm-amd
            fi
        fi
    fi
    sudo modprobe vhost_net
}

function _enable_rc_local {
    if [ ! -f /etc/rc.d/rc.local ]; then
        sudo mkdir -p /etc/rc.d/
        echo '#!/bin/bash' | sudo tee /etc/rc.d/rc.local
    fi
    if [ ! -f /etc/systemd/system/rc-local.service ]; then
        sudo bash -c 'cat << EOL > /etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.d/rc.local Compatibility
ConditionPathExists=/etc/rc.d/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.d/rc.local
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOL'
    fi

    sudo chmod +x /etc/rc.d/rc.local
    sudo systemctl --now enable rc-local
}

# create_sriov_vfs() - Function that creates Virtual Functions for Single Root I/O Virtualization (SR-IOV)
function create_sriov_vfs {
    _enable_rc_local
    for nic in $(sudo lshw -C network -short | grep Connection | awk '{ print $2 }'); do
        if [ -e "/sys/class/net/$nic/device/sriov_numvfs" ]  && grep -e up "/sys/class/net/$nic/operstate" > /dev/null ; then
            sriov_numvfs=$(cat "/sys/class/net/$nic/device/sriov_totalvfs")
            echo 0 | sudo tee "/sys/class/net/$nic/device/sriov_numvfs"
            echo "$sriov_numvfs" | sudo tee "/sys/class/net/$nic/device/sriov_numvfs"
            if ! grep "$nic/device/sriov_numvf" /etc/rc.d/rc.local; then
                echo "echo '$sriov_numvfs' > /sys/class/net/$nic/device/sriov_numvfs" | sudo tee --append /etc/rc.d/rc.local
            fi
            msg+="- INFO: $sriov_numvfs SR-IOV Virtual Functions enabled on $nic\n"
        fi
    done
}

# create_qat_vfs() - Function that install Intel QuickAssist Technology drivers and enabled its Virtual Functions
function create_qat_vfs {
    _enable_rc_local

    for qat_dev in $(for i in 0434 0435 37c8 6f54 19e2; do lspci -d 8086:$i -m; done|awk '{print $1}'); do
        qat_numvfs=$(cat "/sys/bus/pci/devices/0000:$qat_dev/sriov_totalvfs")
        echo 0 | sudo tee "/sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs"
        echo "$qat_numvfs" | sudo tee "/sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs"
        if ! grep "/0000:$qat_dev/sriov_numvfs" /etc/rc.d/rc.local; then
            echo "echo '$qat_numvfs' > /sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs" | sudo tee --append /etc/rc.d/rc.local
        fi
        msg+="- INFO: $qat_numvfs QAT Virtual Functions enabled on $qat_dev\n"
    done
}

# _vercmp() - Function that compares two versions
function _vercmp {
    local v1=$1
    local op=$2
    local v2=$3
    local result

    # sort the two numbers with sort's "-V" argument.  Based on if v2
    # swapped places with v1, we can determine ordering.
    result=$(echo -e "$v1\n$v2" | sort -V | head -1)

    case $op in
        "==")
            [ "$v1" = "$v2" ]
            return
            ;;
        ">")
            [ "$v1" != "$v2" ] && [ "$result" = "$v2" ]
            return
            ;;
        "<")
            [ "$v1" != "$v2" ] && [ "$result" = "$v1" ]
            return
            ;;
        ">=")
            [ "$result" = "$v2" ]
            return
            ;;
        "<=")
            [ "$result" = "$v1" ]
            return
            ;;
        *)
            die $LINENO "unrecognised op: $op"
            ;;
    esac
}

function check_qemu {
    if command -v qemu-system-x86_64; then
        qemu_version_installed=$(qemu-system-x86_64 --version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
        if _vercmp "${qemu_version_installed}" '>' "2.6.0"; then
            if [ -f /etc/libvirt/qemu.conf ]; then
                # Permissions required to enable Pmem in QEMU
                sudo sed -i "s/#security_driver .*/security_driver = \"none\"/" /etc/libvirt/qemu.conf
            fi
            if [ -f /etc/apparmor.d/abstractions/libvirt-qemu ]; then
                sudo sed -i "s|  /{dev,run}/shm .*|  /{dev,run}/shm rw,|"  /etc/apparmor.d/abstractions/libvirt-qemu
            fi
            sudo systemctl restart libvirtd
            return
        else
            # NOTE: PMEM in QEMU (https://nvdimm.wiki.kernel.org/pmem_in_qemu)
            msg+="- WARN: PMEM support in QEMU is available since 2.6.0"
            msg+=" version. This host server is using the ${qemu_version_installed} version.\n"
        fi
    fi

    msg+="- INFO: Installing QEMU $PKG_QEMU_VERSION version\n"
    curl -fsSL http://bit.ly/install_pkg | PKG="qemu" bash
}

function exit_trap() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        set +o xtrace
    fi
    printf "CPU usage: "
    grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage " %"}'
    printf "Memory free(Kb): "
    awk -v low="$(grep low /proc/zoneinfo | awk '{k+=$2}END{print k}')" '{a[$1]=$2}  END{ print a["MemFree:"]+a["Active(file):"]+a["Inactive(file):"]+a["SReclaimable:"]-(12*low);}' /proc/meminfo
    echo "Environment variables:"
    printenv
    echo -e "$msg"
    exit 1
}

if ! sudo -n "true"; then
    echo ""
    echo "passwordless sudo is needed for '$(id -nu)' user."
    echo "Please fix your /etc/sudoers file. You likely want an"
    echo "entry like the following one..."
    echo ""
    echo "$(id -nu) ALL=(ALL) NOPASSWD: ALL"
    exit 1
fi

trap exit_trap ERR

# shellcheck disable=SC1091
source /etc/os-release || source /usr/lib/os-release
case ${ID,,} in
    *suse*)
        CONFIGURE_ARGS="with-libvirt-include=/usr/include/libvirt with-libvirt-lib=/usr/lib64"
        export CONFIGURE_ARGS
        sudo zypper -n ref
        INSTALLER_CMD="sudo -H -E zypper -q install -y --no-recommends"
    ;;
    ubuntu|debian)
        echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
        sudo apt-get update
        INSTALLER_CMD="sudo -H -E apt-get -y -q=3 install"
    ;;
    rhel|centos|fedora)
        PKG_MANAGER=$(command -v dnf || command -v yum)
        INSTALLER_CMD="sudo -H -E ${PKG_MANAGER} -q -y install"
        if ! sudo "$PKG_MANAGER" repolist | grep "epel/"; then
            $INSTALLER_CMD epel-release
        fi
        sudo "$PKG_MANAGER" updateinfo --assumeyes
    ;;
esac

pkgs="vagrant"
case ${PROVIDER} in
    virtualbox)
        pkgs+=" virtualbox"
    ;;
    libvirt)
        $INSTALLER_CMD qemu || :
        pkgs+=" bridge-utils dnsmasq ebtables libvirt"
        pkgs+=" qemu-kvm ruby-devel gcc nfs make"
    ;;
esac
if [ "${CREATE_SRIOV_VFS:-false}" == "true" ]; then
    pkgs+=" sysfsutils lshw"
fi
if [ "${CREATE_QAT_VFS:-false}" == "true" ]; then
    pkgs+=" qat-driver"
fi

curl -fsSL http://bit.ly/install_pkg | PKG="$pkgs" PKG_UPDATE=true bash
msg+="- INFO: Installing vagrant $PKG_VAGRANT_VERSION\n"

if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ] || [ -n "${NO_PROXY:-}" ]; then
    vagrant plugin install vagrant-proxyconf
fi
if [ "${PROVIDER}" == "libvirt" ]; then
    msg+="- INFO: Installing vagrant-libvirt plugin\n"
    vagrant plugin install vagrant-libvirt
    check_qemu
    enable_iommu
    enable_nested_virtualization
fi
vagrant plugin install vagrant-reload

if [ "${CREATE_SRIOV_VFS:-false}" == "true" ]; then
    create_sriov_vfs
    msg+="- INFO: SR-IOV Virtual Functions were created\n"
fi
if [ "${CREATE_QAT_VFS:-false}" == "true" ]; then
    create_qat_vfs
    msg+="- INFO: The Intel QuickAssist Technology drivers were installed using the $PKG_QAT_DRIVER_VERSION version\n"
fi

echo -e "$msg"
