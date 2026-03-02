# CSSE3010 WSL
A custom NixOS image for WSL to provide a reproducible install environment for students of CSSE3010.

## How to build
From a NixOS installation:
    1. Clone this repository
    2. Run `nix build .#nixosConfigurations.csse3010-wsl.config.system.build.tarballBuilder`
    3. Run `sudo ./result/bin/nixos-wsl-tarball-builder`
    4. Install the resultant `nixos.wsl` file to WSL

