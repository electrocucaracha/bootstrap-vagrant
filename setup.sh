#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2019,2022
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o nounset
set -o errexit
set -o pipefail

msg="Summary \n"
export PKG_VAGRANT_VERSION=${PKG_VAGRANT_VERSION:-2.4.9}
export PKG_VIRTUALBOX_VERSION=6.1
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

function _enable_dnssec {
    if [ -f /etc/dnsmasq.d/libvirt-daemon ] && ! grep -q "^dnssec$" /etc/dnsmasq.d/libvirt-daemon; then
        msg+="- INFO: DNSSEC was enabled in dnsmasq service\n"
        echo dnssec | sudo tee --append /etc/dnsmasq.d/libvirt-daemon
    fi
}

function _enable_iommu {
    if ! iommu_support=$(sudo virt-host-validate qemu | grep 'Checking for device assignment IOMMU support'); then
        echo "- WARN - IOMMU support checker reported: $(awk -F':' '{print $3}' <<<"$iommu_support")"
    fi
    if sudo virt-host-validate qemu | grep -q 'Checking if IOMMU is enabled by kernel'; then
        return
    fi
    if [[ ${ID,,} == *clear-linux-os* ]]; then
        mkdir -p /etc/kernel/cmdline.d
        echo "intel_iommu=on" | sudo tee /etc/kernel/cmdline.d/enable-iommu.conf
    else
        if [ -f /etc/default/grub ] && [[ "$(grep "GRUB_CMDLINE_LINUX=" /etc/default/grub)" != *intel_iommu=on* ]]; then
            sudo sed -i "s|^GRUB_CMDLINE_LINUX=\(.*\)\"|GRUB_CMDLINE_LINUX=\1 intel_iommu=on\"|g" /etc/default/grub
        fi
    fi
    _reload_grub
    msg+="- WARN: IOMMU was enabled and requires to reboot the server to take effect\n"
}

function _enable_nested_virtualization {
    vendor_id=$(lscpu | grep "Vendor ID")
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

function _create_sriov_vfs {
    _enable_rc_local
    for nic in $(sudo lshw -C network -short | grep Connection | awk '{ print $2 }'); do
        if [ -e "/sys/class/net/$nic/device/sriov_numvfs" ] && grep -e up "/sys/class/net/$nic/operstate" >/dev/null; then
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
        echo "unrecognised op: $op"
        exit 1
        ;;
    esac
}

function _check_qemu {
    if command -v qemu-system-x86_64; then
        qemu_version_installed=$(qemu-system-x86_64 --version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
        if _vercmp "${qemu_version_installed}" '>' "2.6.0"; then
            if [ -f /etc/libvirt/qemu.conf ]; then
                # Permissions required to enable Pmem in QEMU
                sudo sed -i 's/#security_driver .*/security_driver = "none"/' /etc/libvirt/qemu.conf
            fi
            if [ -f /etc/apparmor.d/abstractions/libvirt-qemu ]; then
                sudo sed -i "s|  /{dev,run}/shm .*|  /{dev,run}/shm rw,|" /etc/apparmor.d/abstractions/libvirt-qemu
            fi
            sudo systemctl restart libvirtd
        else
            # NOTE: PMEM in QEMU (https://nvdimm.wiki.kernel.org/pmem_in_qemu)
            msg+="- WARN: PMEM support in QEMU is available since 2.6.0"
            msg+=" version. This host server is using the ${qemu_version_installed} version.\n"
        fi
    fi
}

function _exit_trap() {
    if [[ ${DEBUG:-false} == "true" ]]; then
        set +o xtrace
    fi
    printf "CPU usage: "
    grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage " %"}'
    printf "Memory free(Kb): "
    awk -v low="$(grep low /proc/zoneinfo | awk '{k+=$2}END{print k}')" '{a[$1]=$2}  END{ print a["MemFree:"]+a["Active(file):"]+a["Inactive(file):"]+a["SReclaimable:"]-(12*low);}' /proc/meminfo
    echo "Environment variables:"
    printenv
}

function _check_reqs {
    if ! sudo -n "true"; then
        echo ""
        echo "passwordless sudo is needed for '$(id -nu)' user."
        echo "Please fix your /etc/sudoers file. You likely want an"
        echo "entry like the following one..."
        echo ""
        echo "$(id -nu) ALL=(ALL) NOPASSWD: ALL"
        exit 1
    fi
}

function _install_deps {
    CONFIGURE_ARGS="with-libvirt-include=/usr/include/libvirt"
    # shellcheck disable=SC1091
    source /etc/os-release || source /usr/lib/os-release
    case ${ID,,} in
    *suse*)
        if [ "${PROVIDER}" == "libvirt" ]; then
            # https://github.com/hashicorp/vagrant/issues/12138
            export PKG_VAGRANT_VERSION=2.2.13
        fi
        sudo zypper -n ref
        INSTALLER_CMD="sudo -H -E zypper -q install -y --no-recommends"
        CONFIGURE_ARGS+=" with-libvirt-lib=/usr/lib64"
        ;;
    ubuntu | debian)
        echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
        sudo apt-get update
        INSTALLER_CMD="sudo -H -E apt-get -y -q=3 install"
        CONFIGURE_ARGS+=" with-libvirt-lib=/usr/lib"
        ;;
    rhel | centos | fedora | rocky)
        PKG_MANAGER=$(command -v dnf || command -v yum)
        INSTALLER_CMD="sudo -H -E ${PKG_MANAGER} -q -y install"
        if ! sudo "$PKG_MANAGER" repolist | grep "epel/"; then
            $INSTALLER_CMD epel-release
        fi
        sudo "$PKG_MANAGER" updateinfo --assumeyes
        CONFIGURE_ARGS+=" with-libvirt-lib=/usr/lib64"
        ;;
    esac
    export CONFIGURE_ARGS

    pkgs="vagrant"
    group="vboxusers"
    case ${PROVIDER} in
    virtualbox)
        pkgs+=" virtualbox"
        ;;
    libvirt)
        $INSTALLER_CMD qemu || :
        pkgs=" libvirt qemu-kvm dnsmasq vagrant make"
        if [[ ${ID,,} == "ubuntu" ]] && _vercmp "$VERSION_ID" '>=' "22.04"; then
            pkgs+=" guestfs-tools"
        fi
        if [[ "suse" =~ (^|[[:space:]])${ID,,}($|[[:space:]]) ]]; then
            pkgs+=" polkit"
        fi
        if ! [[ "centos rocky" =~ (^|[[:space:]])${ID,,}($|[[:space:]]) ]]; then
            pkgs+=" notification-daemon vagrant-libvirt qemu-utils"
        else
            sudo dnf config-manager --set-enabled crb
            sudo dnf install -y '@Virtualization Hypervisor' '@Virtualization Tools' '@Development Tools' 'libvirt-devel'
        fi

        # Make kernel image world-readable required for supermin
        if command -v dpkg-statoverride; then
            sudo dpkg-statoverride --update --add root root 0644 "/boot/vmlinuz-$(uname -r)" || :
        fi
        group="kvm"
        ;;
    esac
    if [ "${CREATE_SRIOV_VFS:-false}" == "true" ]; then
        pkgs+=" sysfsutils lshw"
    fi

    curl -fsSL http://bit.ly/install_pkg | PKG="$pkgs" PKG_UPDATE=true bash
    msg+="- INFO: Installing vagrant $PKG_VAGRANT_VERSION\n"
    if (! groups | grep -q "$group") || (! getent group "$group" | grep -q "$USER"); then
        msg+="- INFO: Adding $USER to $group group\n"
        sudo usermod -aG "$group" "$USER"
    fi
}

function _install_plugins {
    if [ -n "${HTTP_PROXY-}" ] || [ -n "${HTTPS_PROXY-}" ] || [ -n "${NO_PROXY-}" ]; then
        vagrant plugin install vagrant-proxyconf
    fi
    if [ "${PROVIDER}" == "libvirt" ]; then
        msg+="- INFO: Installing vagrant-libvirt plugin\n"
        # NOTE: Use workaround https://github.com/hashicorp/vagrant/issues/12445
        if _vercmp "${PKG_VAGRANT_VERSION}" '==' "2.2.17"; then
            sudo ln -s /opt/vagrant/embedded/include/ruby-3.0.0/ruby/st.h /opt/vagrant/embedded/include/ruby-3.0.0/st.h
            export CFLAGS="-I/opt/vagrant/embedded/include/ruby-3.0.0/ruby"
        fi
        vagrant plugin install vagrant-libvirt
        unset CFLAGS
        _check_qemu
        _enable_iommu
        _enable_dnssec
        _enable_nested_virtualization
    fi
    vagrant plugin install vagrant-reload
    vagrant plugin install vagrant-packet
}

function _configure_addons {
    if [ "${CREATE_SRIOV_VFS:-false}" == "true" ]; then
        _create_sriov_vfs
        msg+="- INFO: SR-IOV Virtual Functions were created\n"
    fi
}

function main {
    _check_reqs

    trap _exit_trap ERR
    trap 'echo -e $msg' EXIT

    _install_deps
    _install_plugins
    _configure_addons
}

if [[ ${__name__:-"__main__"} == "__main__" ]]; then
    main
fi
