# Bootstrap Vagrant
[![Build Status](https://travis-ci.org/electrocucaracha/bootstrap-vagrant.png)](https://travis-ci.org/electrocucaracha/bootstrap-vagrant)

This project was created to ensure that [setup.sh](setup.sh)
bash script is able to install [Vagrant tool][1] in different Linux
Distributions. It covers the installation of its dependencies, plugins
and providers.

## Linux Distros

| Name       | Version     |
|:-----------|:-----------:|
| Ubuntu     | 16.04/18.04 |
| CentOS     | 7           |
| OpenSUSE   | Tumbleweed  |
| ClearLinux | 31130       |

## Vagrant Providers

| Name       | Version |
|:-----------|:-------:|
| VirtualBox | 6.0     |
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
| ENABLE_VAGRANT_INSTALL | true    | Enable or disable the installation of Vagrant tools |

## License

Apache-2.0

[1]: https://www.vagrantup.com/
