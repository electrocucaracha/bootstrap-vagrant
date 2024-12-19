# Bootstrap Vagrant
<!-- markdown-link-check-disable-next-line -->
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Super-Linter](https://github.com/electrocucaracha/bootstrap-vagrant/workflows/Lint%20Code%20Base/badge.svg)](https://github.com/marketplace/actions/super-linter)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)
<!-- markdown-link-check-disable-next-line -->
![visitors](https://visitor-badge.laobi.icu/badge?page_id=electrocucaracha.bootstrap-vagrant)
[![Scc Code Badge](https://sloc.xyz/github/electrocucaracha/bootstrap-vagrant?category=code)](https://github.com/boyter/scc/)
[![Scc COCOMO Badge](https://sloc.xyz/github/electrocucaracha/bootstrap-vagrant?category=cocomo)](https://github.com/boyter/scc/)

This project was created to ensure that [setup.sh](setup.sh) bash script is able
to install [Vagrant tool][1] in different Linux Distributions. It covers the
installation of its dependencies, plugins and providers.

## Linux Distros supported

| Name       | Version         |
|:-----------|:---------------:|
| Ubuntu     | 20.04/22.04     |
| Rocky      | 9               |
| openSUSE   | Tumbleweed/Leap |

## Vagrant Providers supported

| Name       | Version |
|:-----------|:-------:|
| VirtualBox | 6.1     |
| Libvirt    |         |

## Vagrant Plugins installed

* vagrant-proxyconf
* vagrant-libvirt
* vagrant-reload
* vagrant-packet
* vagrant-google


## How use this script?

The [setup.sh](setup.sh) bash script has been designed to be consumed remotely
and executed multiple times.

    curl -fsSL http://bit.ly/initVagrant | PROVIDER=libvirt bash

### Environment variables

| Name                   | Default | Description                                         |
|:-----------------------|:-------:|:----------------------------------------------------|
| PROVIDER               |         | Specifies the Vagrant Provider to be installed      |
| CREATE_SRIOV_VFS       | false   | Creates SR-IOV Virtual Functions                    |
| CREATE_QAT_VFS         | false   | Creates QuickAssit Virtual Functions                |

## Contribution

This is an open project, several individuals contribute in different forms like
coding, documenting, testing, spreading the word at events within others.

Thanks to all the people who already contributed!

<a href="https://github.com/electrocucaracha/bootstrap-vagrant/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=electrocucaracha/bootstrap-vagrant" />
</a>

![Visualization of the codebase](./codebase-structure.svg)

[1]: https://www.vagrantup.com/
