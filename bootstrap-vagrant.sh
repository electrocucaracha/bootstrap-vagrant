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

: "${PROVIDER:=libvirt}"

msg="Summary \n"

# shellcheck disable=SC1091
source /etc/os-release || source /usr/lib/os-release
case ${ID,,} in
    *suse)
    INSTALLER_CMD="sudo -H -E zypper -q install -y --no-recommends"
    sudo zypper -n ref
    ;;

    ubuntu|debian)
    libvirt_group="libvirtd"
    INSTALLER_CMD="sudo -H -E apt-get -y -q=3 install"
    sudo apt-get update
    ;;

    rhel|centos|fedora)
    PKG_MANAGER=$(command -v dnf || command -v yum)
    INSTALLER_CMD="sudo -H -E ${PKG_MANAGER} -q -y install"
    if ! sudo "$PKG_MANAGER" repolist | grep "epel/"; then
        $INSTALLER_CMD epel-release
    fi
    sudo "$PKG_MANAGER" updateinfo

    disable_ipv6
    ;;
esac

if ! command -v wget; then
    $INSTALLER_CMD wget
fi

function _reload_grub {
    if command -v grub-mkconfig; then
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
    iommu_support=$(sudo virt-host-validate | grep 'Checking for device assignment IOMMU support')
    if [[ "$iommu_support" != *PASS* ]]; then
        echo "- WARN - IOMMU support checker reported: $(awk -F':' '{print $3}' <<< "$iommu_support")"
    fi
    iommu_validation=$(sudo virt-host-validate | grep 'Checking if IOMMU is enabled by kernel')
    if [[ "$iommu_validation" == *PASS* ]]; then
        return
    fi
    if [ -f /etc/default/grub ]  && [[ "$(grep GRUB_CMDLINE_LINUX /etc/default/grub)" != *intel_iommu=on* ]]; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX\(.*\)\"|GRUB_CMDLINE_LINUX\1 intel_iommu=on\"|g" /etc/default/grub
    fi
    _reload_grub
    msg+="- WARN: IOMMU was enabled and requires to reboot the server to take effect\n"
}

function enable_nested_virtualization {
    vendor_id=$(lscpu|grep "Vendor ID")
    if [[ $vendor_id == *GenuineIntel* ]]; then
        kvm_ok=$(cat /sys/module/kvm_intel/parameters/nested)
        if [[ $kvm_ok == 'N' ]]; then
            msg+="- INFO: Intel Nested-Virtualization was enabled\n"
            sudo rmmod kvm-intel
            echo 'options kvm-intel nested=y' | sudo tee --append /etc/modprobe.d/dist.conf
            sudo modprobe kvm-intel
        fi
    else
        kvm_ok=$(cat /sys/module/kvm_amd/parameters/nested)
        if [[ $kvm_ok == '0' ]]; then
            msg+="- INFO: AMD Nested-Virtualization was enabled\n"
            sudo rmmod kvm-amd
            echo 'options kvm-amd nested=1' | sudo tee --append /etc/modprobe.d/dist.conf
            sudo modprobe kvm-amd
        fi
    fi
    sudo modprobe vhost_net
}

function disable_ipv6 {
    if [ ! -f /proc/net/if_inet6 ]; then
        return
    fi
    if [ -f /etc/default/grub ]  && [[ "$(grep GRUB_CMDLINE_LINUX /etc/default/grub)" != *ipv6.disable=1* ]]; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX\(.*\)\"|GRUB_CMDLINE_LINUX\1 ipv6.disable=1\"|g" /etc/default/grub
    fi
    _reload_grub
    msg+="- WARN: IPv6 was disabled and requires to reboot the server to take effect\n"
}

function create_sriov_vfs {
    for nic in $(sudo lshw -C network -short | grep Connection | awk '{ print $2 }'); do
        if [ -e "/sys/class/net/$nic/device/sriov_numvfs" ]  && grep -e up "/sys/class/net/$nic/operstate" > /dev/null ; then
            sriov_numvfs=$(cat "/sys/class/net/$nic/device/sriov_totalvfs")
            echo 0 | sudo tee "/sys/class/net/$nic/device/sriov_numvfs"
            echo "$sriov_numvfs" | sudo tee "/sys/class/net/$nic/device/sriov_numvfs"
            msg+="- INFO: $sriov_numvfs SR-IOV Virtual Functions enabled on $nic"
        fi
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

function install_vagrant {
    local vagrant_version=2.2.5

    if command -v vagrant; then
        if _vercmp "$(vagrant version | awk 'NR==1{print $3}')" '>=' "vagrant_version"; then
            return
        fi
    fi

    vagrant_pkg=""
    case ${ID,,} in
        *suse)
            vagrant_pgp="pgp_keys.asc"
            vagrant_pkg="vagrant_${vagrant_version}_x86_64.rpm"
            wget -q "https://keybase.io/hashicorp/$vagrant_pgp"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            gpg --quiet --with-fingerprint "$vagrant_pgp"
            sudo rpm --import "$vagrant_pgp"
            sudo rpm --checksig "$vagrant_pkg"
            sudo rpm --install "$vagrant_pkg"
            rm $vagrant_pgp
        ;;
        ubuntu|debian)
            vagrant_pkg="vagrant_${vagrant_version}_x86_64.deb"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            sudo dpkg -i "$vagrant_pkg"
        ;;
        rhel|centos|fedora)
            vagrant_pkg="vagrant_${vagrant_version}_x86_64.rpm"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            $INSTALLER_CMD "$vagrant_pkg"
        ;;
    esac
    rm "$vagrant_pkg"
    if [[ ${HTTP_PROXY+x} = "x"  ]]; then
        vagrant plugin install vagrant-proxyconf
    fi
    vagrant plugin install vagrant-reload
}

function install_virtualbox {
    local virtualbox_version="6.0"

    if command -v VBoxManage; then
        return
    fi

    case ${ID,,} in
        *suse)
            wget -q "http://download.virtualbox.org/virtualbox/rpm/opensuse/$VERSION/virtualbox.repo" -P /etc/zypp/repos.d/
            wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | rpm --import -
        ;;
        ubuntu|debian)
            echo "deb http://download.virtualbox.org/virtualbox/debian trusty contrib" | sudo tee --append /etc/apt/sources.list
            wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
            wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
        ;;
        rhel|centos|fedora)
            wget -q http://download.virtualbox.org/virtualbox/rpm/rhel/virtualbox.repo -P /etc/yum.repos.d
            wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | rpm --import -
        ;;
    esac
    $INSTALLER_CMD "VirtualBox-$virtualbox_version dkms"
}

function install_qemu {
    local qemu_version=4.1.0
    local qemu_tarball="qemu-${qemu_version}.tar.xz"

    if command -v qemu-system-x86_64; then
        qemu_version=$(qemu-system-x86_64 --version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
        if _vercmp "${qemu_version}" '>' "2.6.0"; then
            # Permissions required to enable Pmem in QEMU
            sudo sed -i "s/#security_driver .*/security_driver = \"none\"/" /etc/libvirt/qemu.conf
            if [ -f /etc/apparmor.d/abstractions/libvirt-qemu ]; then
                sudo sed -i "s|  /{dev,run}/shm .*|  /{dev,run}/shm rw,|"  /etc/apparmor.d/abstractions/libvirt-qemu
            fi
            sudo systemctl restart libvirtd
        else
            # NOTE: PMEM in QEMU (https://nvdimm.wiki.kernel.org/pmem_in_qemu)
            msg+="- WARN: PMEM support in QEMU is available since 2.6.0"
            msg+=" version. This host server is using the\n"
            msg+=" ${qemu_version} version. For more information about"
            msg+=" QEMU in Linux go to QEMU official website (https://wiki.qemu.org/Hosts/Linux)\n"
            msg+=" or use the bootstrap-qemu.sh script provided by this project"
        fi
        return
    fi

    case ${ID,,} in
        rhel|centos|fedora)
            $INSTALLER_CMD epel-release
            $INSTALLER_CMD glib2-devel libfdt-devel pixman-devel zlib-devel wget python3 libpmem-devel numactl-devel
            sudo -H -E "${PKG_MANAGER}" -q -y group install "Development Tools"
        ;;
    esac

    wget -c "https://download.qemu.org/$qemu_tarball"
    tar xvf "$qemu_tarball"
    rm -rf "$qemu_tarball"
    pushd "qemu-${qemu_version}" || exit
    ./configure --target-list=x86_64-softmmu --enable-libpmem --enable-numa --enable-kvm
    make
    sudo make install
    popd || exit
    rm -rf "qemu-${qemu_version}"
}

function install_libvirt {
    if command -v virsh; then
        return
    fi

    libvirt_group="libvirt"
    packages=(qemu )
    case ${ID,,} in
    *suse)
        # vagrant-libvirt dependencies
        packages+=(libvirt libvirt-devel ruby-devel gcc qemu-kvm zlib-devel libxml2-devel libxslt-devel make)
        # NFS
        packages+=(nfs-kernel-server)
    ;;
    ubuntu|debian)
        libvirt_group="libvirtd"
        # vagrant-libvirt dependencies
        packages+=(libvirt-bin ebtables dnsmasq libxslt-dev libxml2-dev libvirt-dev zlib1g-dev ruby-dev cpu-checker)
        # NFS
        packages+=(nfs-kernel-server)
    ;;
    rhel|centos|fedora)
        # vagrant-libvirt dependencies
        packages+=(libvirt libvirt-devel ruby-devel gcc qemu-kvm)
        # NFS
        packages+=(nfs-utils nfs-utils-lib)
        ;;
    esac
    ${INSTALLER_CMD} "${packages[@]}"
    sudo usermod -a -G $libvirt_group "$USER" # This might require to reload user's group assigments


    # Start statd service to prevent NFS lock errors
    sudo systemctl enable rpc-statd
    sudo systemctl start rpc-statd

    if command -v firewall-cmd && systemctl is-active --quiet firewalld; then
        for svc in nfs rpc-bind mountd; do
            sudo firewall-cmd --permanent --add-service="${svc}" --zone=trusted
        done
        sudo firewall-cmd --set-default-zone=trusted
        sudo firewall-cmd --reload
    fi

    case ${ID,,} in
        ubuntu|debian)
        kvm-ok
        ;;
    esac
    vagrant plugin install vagrant-libvirt
}

install_vagrant
case $PROVIDER in
    virtualbox|libvirt)
        install_$PROVIDER
    ;;
    * )
        exit 1
    ;;
esac
export VAGRANT_DEFAULT_PROVIDER=${PROVIDER}

enable_iommu
enable_nested_virtualization
create_sriov_vfs

echo -e "$msg"
