{
  description = "CSSE3010 NixOS-WSL";

  inputs = {
    # Pin to a stable NixOS release. The flake.lock records the exact
    # commit so every student gets byte-identical packages.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }: {
    nixosConfigurations.csse3010-wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
