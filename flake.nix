{
  description = "riskyC1-MC toolchain A: simulation, lint and synthesis checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs:
        let
          # Everything `make ci` needs. mkShell's stdenv supplies the C++
          # compiler Verilator builds with (gcc on Linux, clang on macOS).
          # iverilog runs the unit testbenches and check_top.sh; bash 4+ is
          # needed by run_unit.sh.
          ciTools = with pkgs; [ verilator iverilog yosys python3 gnumake coreutils bash git ];
        in {
          # nix develop: the CI tools plus a waveform viewer where it builds.
          # On macOS, install Surfer with Homebrew instead.
          default = pkgs.mkShell {
            packages = ciTools ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.gtkwave ];
          };

          # nix develop .#ci: no GUI tools, so CI downloads less.
          ci = pkgs.mkShell { packages = ciTools; };
        });
    };
}
