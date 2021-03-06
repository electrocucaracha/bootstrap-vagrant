# Bootstrap Vagrant
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Super-Linter](https://github.com/electrocucaracha/bootstrap-vagrant/workflows/Lint%20Code%20Base/badge.svg)](https://github.com/marketplace/actions/super-linter)
![visitors](https://visitor-badge.glitch.me/badge?page_id=electrocucaracha.bootstrap-vagrant)

This project was created to ensure that [setup.sh](setup.sh)
bash script is able to install [Vagrant tool][1] in different Linux
Distributions. It covers the installation of its dependencies, plugins
and providers.

## Linux Distros

| Name       | Version     |
|:-----------|:-----------:|
| Ubuntu     | 18.04/20.04 |
| CentOS     | 7/8         |
| openSUSE   | Tumbleweed  |

## Vagrant Providers

| Name       | Version |
|:-----------|:-------:|
| VirtualBox | 6.1     |
| Libvirt    |         |

## Vagrant Plugins

* vagrant-proxyconf
* vagrant-libvirt
* vagrant-reload

## How use this script?

The [setup.sh](setup.sh) bash script has been designed to be consumed
remotely and executed multiple times.

    curl -fsSL http://bit.ly/initVagrant | PROVIDER=libvirt bash

After the execution of the script, the *~/boostrap-vagrant.log* file
is created to summarize the actions that were taken.

### Environment variables

| Name                   | Default | Description                                         |
|:-----------------------|:-------:|:----------------------------------------------------|
| PROVIDER               |         | Specifies the Vagrant Provider to be installed      |
| CREATE_SRIOV_VFS       | false   | Creates SR-IOV Virtual Functions                    |
| CREATE_QAT_VFS         | false   | Creates QuickAssit Virtual Functions                |

[1]: https://www.vagrantup.com/
