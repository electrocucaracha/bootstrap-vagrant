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
vagrant_version=2.2.5
virtualbox_version=6.0
qemu_version=4.1.0
if [ "${DEBUG:-false}" == "true" ]; then
    set -o xtrace
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
    if ! iommu_support=$(sudo virt-host-validate qemu | grep 'Checking for device assignment IOMMU support'); then
        echo "- WARN - IOMMU support checker reported: $(awk -F':' '{print $3}' <<< "$iommu_support")"
    fi
    if sudo virt-host-validate qemu | grep 'Checking if IOMMU is enabled by kernel'; then
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

function _install_sysfsutils {
    $INSTALLER_CMD sysfsutils
    if [ ! -f /etc/rc.d/rc.local ]; then
        sudo mkdir -p /etc/rc.d/
        sudo touch /etc/rc.d/rc.local
    fi
    sudo chmod +x /etc/rc.d/rc.local
}

# create_sriov_vfs() - Function that creates Virtual Functions for Single Root I/O Virtualization (SR-IOV)
function create_sriov_vfs {
    if ! command -v lshw; then
        if [[ "${ID,,}" == *opensuse* ]]; then
            $INSTALLER_CMD lshw
        else
            $INSTALLER_CMD hwloc
        fi
    fi
    _install_sysfsutils
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

function _install_qat_driver {
    local qat_driver_version="1.7.l.4.6.0-00025" # Jul 23, 2019 https://01.org/intel-quick-assist-technology/downloads
    local qat_driver_tarball="qat${qat_driver_version}.tar.gz"
    if systemctl is-active --quiet qat_service; then
        return
    fi

    if [ ! -d /tmp/qat ]; then
        wget -O $qat_driver_tarball "https://01.org/sites/default/files/downloads/${qat_driver_tarball}"
        sudo mkdir -p /tmp/qat
        sudo tar -C /tmp/qat -xzf "$qat_driver_tarball"
        rm "$qat_driver_tarball"
    fi

    case ${ID,,} in
        opensuse*)
            sudo -H -E zypper -q install -y -t pattern devel_C_C++
            sudo -H -E zypper -q install -y --no-recommends pciutils libudev-devel openssl-devel gcc-c++ kernel-source kernel-syms
            msg+="- WARN: The Intel QuickAssist Technology drivers don't have full support in {ID,,} yet.\n"
            return
        ;;
        ubuntu|debian)
            sudo -H -E apt-get -y -q=3 install build-essential "linux-headers-$(uname -r)" pciutils libudev-dev
        ;;
        rhel|centos|fedora)
            PKG_MANAGER=$(command -v dnf || command -v yum)
            sudo "${PKG_MANAGER}" groups mark install "Development Tools"
            sudo "${PKG_MANAGER}" groups install -y "Development Tools"
            sudo -H -E "${PKG_MANAGER}" -q -y install "kernel-devel-$(uname -r)" pciutils libudev-devel gcc openssl-devel yum-plugin-fastestmirror
        ;;
    esac

    for mod in $(lsmod | grep "^intel_qat" | awk '{print $4}'); do
        sudo rmmod "$mod"
    done
    if lsmod | grep "^intel_qat"; then
        sudo rmmod intel_qat
    fi

    pushd /tmp/qat
    sudo ./configure --disable-qat-lkcf
    for action in clean uninstall install; do
        sudo make $action
    done
    popd

    sudo systemctl start qat_service
    sudo systemctl enable qat_service
    msg+="- INFO: The Intel QuickAssist Technology drivers were installed using the $qat_driver_version version\n"
}

# create_qat_vfs() - Function that install Intel QuickAssist Technology drivers and enabled its Virtual Functions
function create_qat_vfs {
    _install_qat_driver
    _install_sysfsutils

    sudo modprobe vfio-pci
    for qat_dev in $(for i in 0434 0435 37c8 6f54 19e2; do lspci -d 8086:$i -m; done|awk '{print $1}'); do
        qat_numvfs=$(cat "/sys/bus/pci/devices/0000:$qat_dev/sriov_totalvfs")
        echo 0 | sudo tee "/sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs"
        echo "$qat_numvfs" | sudo tee "/sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs"
        if ! grep "/0000:$qat_dev/sriov_numvfs" /etc/rc.d/rc.local; then
            echo "echo '$qat_numvfs' > /sys/bus/pci/devices/0000:$qat_dev/sriov_numvfs" | sudo tee --append /etc/rc.d/rc.local
        fi
        msg+="- INFO: $qat_numvfs SR-IOV Virtual Functions enabled on $nic\n"
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
    if command -v vagrant; then
        if _vercmp "$(vagrant version | awk 'NR==1{print $3}')" '>=' "$vagrant_version"; then
            return
        fi
    fi

    pushd "$(mktemp -d)"
    msg+="- INFO: Installing vagrant $vagrant_version\n"
    vagrant_pkg="vagrant_${vagrant_version}_x86_64."
    case ${ID,,} in
        opensuse*)
            vagrant_pgp="pgp_keys.asc"
            vagrant_pkg+="rpm"
            wget -q "https://keybase.io/hashicorp/$vagrant_pgp"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            gpg --quiet --with-fingerprint "$vagrant_pgp"
            sudo rpm --import "$vagrant_pgp"
            sudo rpm --checksig "$vagrant_pkg"
            sudo rpm --install "$vagrant_pkg"
            rm $vagrant_pgp
        ;;
        ubuntu|debian)
            vagrant_pkg+="deb"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            sudo dpkg -i "$vagrant_pkg"
        ;;
        rhel|centos|fedora)
            vagrant_pkg+="rpm"
            wget -q "https://releases.hashicorp.com/vagrant/$vagrant_version/$vagrant_pkg"
            $INSTALLER_CMD "$vagrant_pkg"
        ;;
    esac
    rm $vagrant_pkg
    popd
    if [[ ${HTTP_PROXY+x} = "x"  ]]; then
        vagrant plugin install vagrant-proxyconf
    fi
    vagrant plugin install vagrant-reload
}

function install_virtualbox {
    if command -v VBoxManage; then
        return
    fi

    pushd "$(mktemp -d)"
    msg+="- INFO: Installing VirtualBox $virtualbox_version\n"
    wget -q https://www.virtualbox.org/download/oracle_vbox.asc
    case ${ID,,} in
        opensuse*)
            sudo wget -q "http://download.virtualbox.org/virtualbox/rpm/opensuse/virtualbox.repo" -P /etc/zypp/repos.d/
            sudo rpm --import oracle_vbox.asc
        ;;
        ubuntu|debian)
            echo "deb http://download.virtualbox.org/virtualbox/debian $UBUNTU_CODENAME contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
            wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
            sudo apt-key add oracle_vbox.asc
            sudo apt-get update
        ;;
        rhel|centos|fedora)
            sudo wget -q https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo -P /etc/yum.repos.d
            sudo rpm --import oracle_vbox.asc
        ;;
    esac
    rm oracle_vbox.asc
    popd
    $INSTALLER_CMD "VirtualBox-$virtualbox_version" dkms
}

function install_qemu {
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
        fi
        return
    fi

    msg+="- INFO: Installing QEMU $qemu_version\n"
    case ${ID,,} in
        rhel|centos|fedora)
            $INSTALLER_CMD epel-release
            $INSTALLER_CMD glib2-devel libfdt-devel pixman-devel zlib-devel python3 libpmem-devel numactl-devel
            sudo -H -E "${PKG_MANAGER}" -q -y group install "Development Tools"
        ;;
    esac

    pushd "$(mktemp -d)"
    wget -c "https://download.qemu.org/$qemu_tarball"
    tar xvf "$qemu_tarball"
    rm -rf "$qemu_tarball"
    pushd "qemu-${qemu_version}" || exit
    ./configure --target-list=x86_64-softmmu --enable-libpmem --enable-numa --enable-kvm
    make
    sudo make install
    popd || exit
    rm -rf "qemu-${qemu_version}"
    popd
}

function install_libvirt {
    if command -v virsh; then
        return
    fi

    msg+="- INFO: Installing Libvirt\n"
    libvirt_group="libvirt"
    packages=(qemu )
    case ${ID,,} in
    opensuse*)
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
    if command -v vagrant; then
        vagrant plugin install vagrant-libvirt
    fi
}

# shellcheck disable=SC1091
source /etc/os-release || source /usr/lib/os-release
if [[ ${ID+x} = "x"  ]]; then
    id_os="export $(grep "^ID=" /etc/os-release)"
    eval "$id_os"
fi
case ${ID,,} in
    opensuse*)
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

install_vagrant
case ${PROVIDER} in
    libvirt|virtualbox)
        "install_${PROVIDER}"
    ;;
esac

enable_iommu
enable_nested_virtualization
create_sriov_vfs
create_qat_vfs

echo -e "$msg" | tee ~/boostrap-vagrant.log
