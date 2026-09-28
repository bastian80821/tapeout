{
  description = "RV32E CPU development and Verilator simulation environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          verilator
          yosys
          gtkwave
          gcc
          coreutils
          gnumake
          python3
        ];
      };
    };
}
