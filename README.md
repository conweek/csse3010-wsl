# CSSE3010 WSL
A custom NixOS image for WSL to provide a reproducible install environment for students of CSSE3010.
**Note: This is a custom built NixOS image for WSL specifically for the coure CSSE3010 at The University of Queensland. It is not intended for use outside of this course.**

## Features
1. Reproducible development environment for STM32 development (tailored for STM32F429ZI)
2. Integrated scripts for setting up student environment in the background
3. Integrated tools for students to use (GDB-based STM32 Debugging script to set it up for students in one call)
4. VS Code integration
5. USBIPD integration
6. Automatic Git setup
7. MOTD art generator for when students login

## How to build
From a NixOS installation:
1. Clone this repository
2. Run `nix build .#nixosConfigurations.csse3010-wsl.config.system.build.tarballBuilder`
3. Run `sudo ./result/bin/nixos-wsl-tarball-builder`
4. Install the resultant `nixos.wsl` file to WSL

## How to update once installed
From inside WSL, run `update` and it should pull the latest version of this repo and update the system.

