{
  description = "OpenMM plugin to define forces with neural networks";

  # Flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # also valid: "nixpkgs"
  };

  # Flake outputs
  outputs = { self, nixpkgs }:
    let
      # Systems supported
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      # Helper to provide system-specific attributes
      forAllSystems = f:
        nixpkgs.lib.genAttrs allSystems (system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                cudaSupport = true;
              };
            };
          });

    in {
      # Development environment output
      devShells = forAllSystems ({ pkgs }: {
        built = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (python_packages: [
              self.packages.x86_64-linux.openmmtorch-python
              python_packages.torch
            ]))
          ];
          shellHook = ''
            echo 'You are in a nix shell'
          '';
        };
        default = pkgs.mkShell {
          # The Nix packages provided in the environment
          packages = with pkgs; [
            direnv # For setting nix enviroment
            gcc11 # The GNU Compiler Collection
            cmake
            cudaPackages.cudatoolkit
            # Other libraries
            libtorch-bin
            python310Packages.openmm
            swig4
            python310
            python310Packages.pip
          ];
          shellHook = ''
            echo 'You are in a nix shell'
            export LD_LIBRARY_PATH=${pkgs.cudaPackages.cudatoolkit.lib}/lib:$LD_LIBRARY_PATH
            export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}
            export CUDA_LIB=${pkgs.cudaPackages.cudatoolkit.lib}
            export OPENMM_HOME=${pkgs.openmm.override { enableCuda = true; }}
          '';
        };
      });

      packages = forAllSystems ({ pkgs }: {
        openmmtorch-python = pkgs.python310Packages.toPythonModule
          self.packages.x86_64-linux.default;
        default = pkgs.callPackage (import ./default.nix) { };
      });
    };
}
