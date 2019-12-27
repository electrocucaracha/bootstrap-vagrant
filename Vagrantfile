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
# NOTE: This range is based on vagrant-libvirt network definition CIDR 192.168.121.0/24
(1..254).each do |i|
  $no_proxy += ",192.168.121.#{i}"
end
$no_proxy += ",10.0.2.15"

File.exists?("/usr/share/qemu/OVMF.fd") ? loader = "/usr/share/qemu/OVMF.fd" : loader = File.join(File.dirname(__FILE__), "OVMF.fd")
if not File.exists?(loader)
  system('curl -O https://download.clearlinux.org/image/OVMF.fd')
end
distros = YAML.load_file(File.dirname(__FILE__) + '/distros_supported.yml')

Vagrant.configure("2") do |config|
  config.vm.provider :libvirt
  config.vm.provider :virtualbox

  config.vm.synced_folder './', '/vagrant', type: "rsync"
  provider = (ENV['PROVIDER'] || :libvirt).to_sym

  distros.each do |distro|
    config.vm.define "#{distro['name']}_#{provider}" do |node|
      node.vm.box = distro["box"]
      node.vm.box_version = distro["version"]
      node.vm.box_check_update = false
      if distro["name"] == "clearlinux"
        node.vm.provider 'libvirt' do |v|
          v.loader = loader
        end
      end
    end
  end

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
        clear-linux-os)
        sudo mkdir -p /etc/kernel/cmdline.d
        echo "module.sig_unenforce" | sudo tee /etc/kernel/cmdline.d/allow-unsigned-modules.conf
        sudo clr-boot-manager update
        ;;
    esac
  SHELL
  config.vm.provision :reload
  config.vm.provision 'shell', privileged: false do |sh|
    sh.env = {
      'DEBUG': "true"
    }
    sh.inline = <<-SHELL
      set -o xtrace
      cd /vagrant/
      PROVIDER=#{provider} ./setup.sh
    SHELL
  end
  config.vm.provision :reload
  config.vm.provision 'shell', privileged: false do |sh|
    sh.inline = <<-SHELL
      cd /vagrant/
      source /etc/os-release || source /usr/lib/os-release
      ./validate.sh | tee validate_${ID,,}_#{provider}.log
    SHELL
  end

  [:virtualbox, :libvirt].each do |provider|
  config.vm.provider provider do |p|
      p.cpus = 4
      p.memory = 8192
    end
  end

  config.vm.provider :libvirt do |v|
    v.cpu_mode = 'host-passthrough'
    v.nested = true
    v.random_hostname = true
    v.management_network_address = "192.168.121.0/24"
  end

  if ENV['http_proxy'] != nil and ENV['https_proxy'] != nil
    if Vagrant.has_plugin?('vagrant-proxyconf')
      config.proxy.http     = ENV['http_proxy'] || ENV['HTTP_PROXY'] || ""
      config.proxy.https    = ENV['https_proxy'] || ENV['HTTPS_PROXY'] || ""
      config.proxy.no_proxy = $no_proxy
    end
  end
end
