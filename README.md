# Bootstrap Vagrant

<!-- markdown-link-check-disable-next-line -->

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Super-Linter](https://github.com/electrocucaracha/bootstrap-vagrant/workflows/Lint%20Code%20Base/badge.svg)](https://github.com/marketplace/actions/super-linter)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

<!-- markdown-link-check-disable-next-line -->

![visitors](https://visitor-badge.laobi.icu/badge?page_id=electrocucaracha.bootstrap-vagrant)
[![Scc Code Badge](https://sloc.xyz/github/electrocucaracha/bootstrap-vagrant?category=code)](https://github.com/boyter/scc/)
[![Scc COCOMO Badge](https://sloc.xyz/github/electrocucaracha/bootstrap-vagrant?category=cocomo)](https://github.com/boyter/scc/)

Bootstrap Vagrant is a [portable bash script](setup.sh) designed to automate the installation of [Vagrant][1]
and its dependencies across various Linux distributions. It also supports the setup of common Vagrant providers
and plugins, enabling consistent development environments with minimal effort.

## Supported Linux Distributions

| Distribution |  Versions   |
| :----------- | :---------: |
| Ubuntu       | 20.04/22.04 |
| Rocky        |      9      |
| openSUSE     |    Leap     |

## Supported Vagrant Providers

| Provider   | Version |
| :--------- | :-----: |
| VirtualBox |   6.1   |
| Libvirt    |         |

## Installed Vagrant Plugins

- vagrant-proxyconf
- vagrant-libvirt
- vagrant-reload
- vagrant-packet

## Usage

The script is designed to be idempotent and remotely executable.

    curl -fsSL http://bit.ly/initVagrant | PROVIDER=libvirt bash

You can run it multiple times without harmful side effects.

### Environment variables

| Variable         | Default | Description                                 |
| :--------------- | :-----: | :------------------------------------------ |
| PROVIDER         |         | Specifies which Vagrant provider to install |
| CREATE_SRIOV_VFS |  false  | Optionally creates SR-IOV Virtual Functions |

## Contribution

This is an open-source project that welcomes contributions of all kinds: code, documentation, testing, and advocacy.

Thanks to all the people who have contributed so far!

<a href="https://github.com/electrocucaracha/bootstrap-vagrant/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=electrocucaracha/bootstrap-vagrant" alt="Contributors" />
</a>

![Visualization of the codebase](./codebase-structure.svg)

[1]: https://www.vagrantup.com/
