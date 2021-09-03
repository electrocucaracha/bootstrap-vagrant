# -*- mode: ruby -*-
# vi: set ft=ruby :
##############################################################################
# Copyright (c)
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

$no_proxy = ENV['NO_PROXY'] || ENV['no_proxy'] || "127.0.0.1,localhost"
(1..254).each do |i|
  $no_proxy += ",10.0.2.#{i}"
end
$provider = ENV['PROVIDER'] || "libvirt"
$create_sriov_vfs = ENV['CREATE_SRIOV_VFS']
$create_qat_vfs = ENV['CREATE_QAT_VFS']

distros = YAML.load_file(File.dirname(__FILE__) + '/distros_supported.yml')

Vagrant.configure("2") do |config|
  config.vm.provider :libvirt
  config.vm.provider :virtualbox

  config.vm.synced_folder './', '/vagrant'
  distros["linux"].each do |distro|
    config.vm.define "#{distro['alias']}_#{$provider}" do |node|
      node.vm.box = distro["name"]
      node.vm.box_version = "#{distro['version']}"
      node.vm.box_check_update = false
    end
  end

  # Install requirements
  config.vm.provision 'shell', privileged: false, inline: <<-SHELL
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
  config.vm.provision 'shell', privileged: false, inline: <<-SHELL
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
  config.vm.provision 'shell', privileged: false do |sh|
    sh.env = {
      'DEBUG': "true",
      'CREATE_SRIOV_VFS': "#{$create_sriov_vfs}",
      'CREATE_QAT_VFS': "#{$create_qat_vfs}"
    }
    sh.inline = <<-SHELL
      set -o errexit
      cd /vagrant/
      PROVIDER=#{$provider} ./setup.sh | tee  ~/setup.log
    SHELL
  end
  config.vm.provision :reload
  config.vm.provision 'shell', privileged: false do |sh|
    sh.inline = <<-SHELL
      set -o errexit
      cd /vagrant
      ./validate.sh
    SHELL
  end

  host = RbConfig::CONFIG['host_os']
  if host =~ /darwin/
    mem = `sysctl -n hw.memsize`.to_i / 1024
  elsif host =~ /linux/
    mem = `grep 'MemTotal' /proc/meminfo | sed -e 's/MemTotal://' -e 's/ kB//'`.to_i
  elsif host =~ /mswin|mingw|cygwin/
    mem = `wmic computersystem Get TotalPhysicalMemory`.split[1].to_i / 1024
  end
  [:virtualbox, :libvirt].each do |provider|
  config.vm.provider provider do |p|
      p.cpus = ENV['CPUS'] || 1
      p.memory = ENV['MEMORY'] || mem / 1024 / 4
    end
  end

  config.vm.provider :virtualbox do |v|
    v.gui = false
    v.customize ["modifyvm", :id, "--nested-hw-virt","on"]
    # it will cause the NAT gateway to accept DNS traffic and the gateway will
    # read the query and use the host's operating system APIs to resolve it
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    # https://docs.oracle.com/en/virtualization/virtualbox/6.0/user/network_performance.html
    v.customize ["modifyvm", :id, "--nictype1", "virtio", "--cableconnected1", "on"]
    # https://bugs.launchpad.net/cloud-images/+bug/1829625/comments/2
    v.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
    v.customize ["modifyvm", :id, "--uartmode1", "file", File::NULL]
    # Enable nested paging for memory management in hardware
    v.customize ["modifyvm", :id, "--nestedpaging", "on"]
    # Use large pages to reduce Translation Lookaside Buffers usage
    v.customize ["modifyvm", :id, "--largepages", "on"]
    # Use virtual processor identifiers  to accelerate context switching
    v.customize ["modifyvm", :id, "--vtxvpid", "on"]
  end

  config.vm.provider :libvirt do |v, override|
    override.vm.synced_folder "./", "/vagrant", type: "nfs"
    v.cpu_mode = 'host-passthrough'
    v.nested = true
    v.random_hostname = true
    v.management_network_address = "10.0.2.0/24"
    v.management_network_name = "administration"
  end

  if ENV['http_proxy'] != nil and ENV['https_proxy'] != nil
    if Vagrant.has_plugin?('vagrant-proxyconf')
      config.proxy.http     = ENV['http_proxy'] || ENV['HTTP_PROXY'] || ""
      config.proxy.https    = ENV['https_proxy'] || ENV['HTTPS_PROXY'] || ""
      config.proxy.no_proxy = $no_proxy
      config.proxy.enabled = { docker: false, git: false }
    end
  end
end
