# frozen_string_literal: true

# -*- mode: ruby -*-
# vi: set ft=ruby :
##############################################################################
# Copyright (c) 2022
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

no_proxy = ENV["NO_PROXY"] || ENV["no_proxy"] || "127.0.0.1,localhost"
(1..254).each do |i|
  no_proxy += ",10.0.2.#{i}"
end
vagrant_provider = ENV["PROVIDER"] || "libvirt"
create_sriov_vfs = ENV.fetch("CREATE_SRIOV_VFS", nil)

require "yaml"
distros = YAML.load_file("#{File.dirname(__FILE__)}/distros_supported.yml")

Vagrant.configure("2") do |config|
  # rubocop:enable Metrics/BlockLength
  config.vm.provider :libvirt
  config.vm.provider :virtualbox

  config.vm.synced_folder "./", "/vagrant"
  config.vm.synced_folder "./output", "/vagrant/output"
  distros["linux"].each do |distro|
    config.vm.define "#{distro['alias']}_#{vagrant_provider}" do |node|
      node.vm.box = distro["name"]
      node.vm.box_version = (distro["version"]).to_s
      node.vm.box_check_update = false
    end
  end

  # Configure DNS resolver
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    echo "Configure DNS resolver"
    if command -v systemd-resolve && sudo systemd-resolve --status --interface eth0; then
        sudo systemd-resolve --interface eth0 --set-dns 1.1.1.1 --flush-caches
        sudo systemd-resolve --status --interface eth0
    fi
    if [ -f /etc/netplan/01-netcfg.yaml ]; then
        sudo sed -i "s/addresses: .*/addresses: [1.1.1.1, 8.8.8.8, 8.8.4.4]/g" /etc/netplan/01-netcfg.yaml
        sudo netplan apply
    fi
  SHELL

  # Remove unused kernels
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    echo "Remove unused kernels"
    source /etc/os-release || source /usr/lib/os-release
    case ${ID,,} in
        ubuntu|debian)
            sudo apt-get purge -y $(dpkg -l linux-{image,headers}-"[0-9]*" | awk '/ii/{print $2}' | grep -ve "$(uname -r | sed -r 's/-[a-z]+//')")
            sudo apt autoremove -y
        ;;
    esac
  SHELL
  # Install requirements
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    echo "Install requirements"
    if ! command -v curl; then
        source /etc/os-release || source /usr/lib/os-release
        case ${ID,,} in
            ubuntu|debian)
                sudo apt-get update -qq > /dev/null
                sudo apt-get install -y -qq -o=Dpkg::Use-Pty=0 curl
            ;;
        esac
    fi
  SHELL
  # Upgrade Kernel version
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    echo "Upgrade Kernel version"
    source /etc/os-release || source /usr/lib/os-release
    case ${ID,,} in
        rhel|centos|fedora)
        PKG_MANAGER=$(command -v dnf || command -v yum)
        INSTALLER_CMD="sudo -H -E ${PKG_MANAGER} -q -y install"
        if ! sudo "$PKG_MANAGER" repolist | grep "epel/"; then
            $INSTALLER_CMD epel-release
        fi
        sudo "$PKG_MANAGER" updateinfo
        $INSTALLER_CMD kernel
        sudo grub2-set-default 0
        sudo grub2-mkconfig -o "$(sudo readlink -f /etc/grub2.cfg)"
        ;;
    esac
  SHELL
  config.vm.provision :reload
  # Provision server
  config.vm.provision "shell", privileged: false do |sh|
    sh.env = {
      DEBUG: "true",
      CREATE_SRIOV_VFS: create_sriov_vfs.to_s
    }
    sh.inline = <<-SHELL
      echo "Provision server"
      set -o errexit
      cd /vagrant/
      PROVIDER=#{vagrant_provider} ./setup.sh | tee  /vagrant/output/setup.log
    SHELL
  end
  config.vm.provision :reload
  config.vm.provision "shell", privileged: false do |sh|
    sh.inline = <<-SHELL
      echo "Validate installation"
      set -o errexit
      cd /vagrant
      ./validate.sh
    SHELL
  end

  host = RbConfig::CONFIG["host_os"]
  case host
  when /darwin/
    mem = `sysctl -n hw.memsize`.to_i / 1024
  when /linux/
    mem = `grep 'MemTotal' /proc/meminfo | sed -e 's/MemTotal://' -e 's/ kB//'`.to_i
  when /mswin|mingw|cygwin/
    mem = `wmic computersystem Get TotalPhysicalMemory`.split[1].to_i / 1024
  end
  %i[virtualbox libvirt].each do |provider|
    config.vm.provider provider do |p|
      p.cpus = ENV["CPUS"] || 1
      p.memory = ENV["MEMORY"] || (mem / 1024 / 4)
    end
  end

  config.vm.provider :virtualbox do |v|
    v.gui = false
    v.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    # it will cause the NAT gateway to accept DNS traffic and the gateway will
    # read the query and use the host's operating system APIs to resolve it
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    # https://docs.oracle.com/en/virtualization/virtualbox/6.0/user/network_performance.html
    v.customize ["modifyvm", :id, "--nictype1", "virtio", "--cableconnected1", "on"]
    # Enable nested paging for memory management in hardware
    v.customize ["modifyvm", :id, "--nestedpaging", "on"]
    # Use large pages to reduce Translation Lookaside Buffers usage
    v.customize ["modifyvm", :id, "--largepages", "on"]
    # Use virtual processor identifiers  to accelerate context switching
    v.customize ["modifyvm", :id, "--vtxvpid", "on"]
  end

  config.vm.provider :libvirt do |v, override|
    override.vm.synced_folder "./", "/vagrant", type: "nfs", nfs_version: ENV.fetch("VAGRANT_NFS_VERSION", 3)
    override.vm.synced_folder "./output", "/vagrant/output", type: "nfs",
                                                             nfs_version: ENV.fetch("VAGRANT_NFS_VERSION", 3)
    v.cpu_mode = "host-passthrough"
    v.nested = true
    v.random_hostname = true
    v.management_network_address = "10.0.2.0/24"
    v.management_network_name = "administration"
  end

  if !ENV["http_proxy"].nil? && !ENV["https_proxy"].nil? && Vagrant.has_plugin?("vagrant-proxyconf")
    config.proxy.http = ENV["http_proxy"] || ENV["HTTP_PROXY"] || ""
    config.proxy.https    = ENV["https_proxy"] || ENV["HTTPS_PROXY"] || ""
    config.proxy.no_proxy = no_proxy
    config.proxy.enabled = { docker: false, git: false }
  end
end
