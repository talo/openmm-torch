{
  description = "OpenMM plugin to define forces with neural networks";

  # Flake inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  # Flake outputs
  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      # Systems supported
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
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
              overlays = [
                (final: prev: {
                  c-ares = nixpkgs-unstable.legacyPackages.${system}.c-ares;
                  python311 = prev.python311.override {
                    packageOverrides = pyself: pysuper: {
                      torch = pysuper.torch.overrideAttrs (oldAttrs: {
                        cmakeFlags = (oldAttrs.cmakeFlags or [ ])
                          ++ [ "-DGLIBCXX_USE_CXX11_ABI=1" ];
                      });
                    };
                  };
                  python3 = prev.python3.override {
                    packageOverrides = pyself: pysuper: {
                      torch = pysuper.torch.overrideAttrs (oldAttrs: {
                        cmakeFlags = (oldAttrs.cmakeFlags or [ ])
                          ++ [ "-DGLIBCXX_USE_CXX11_ABI=1" ];
                      });
                    };
                  };
                })
              ];
            };
          });

    in {
      # Development environment output
      devShells = forAllSystems ({ pkgs }: {
        built = pkgs.mkShell {
          packages = [
            (pkgs.python311.withPackages (python_packages: [
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
            gcc13 # The GNU Compiler Collection
            cmake
            cudaPackages.cudatoolkit
            # Other libraries
            python311Packages.torch
            libtorch-bin
            python311Packages.openmm
            swig4
            python311
            python311Packages.pip
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
        openmmtorch-python = pkgs.python311Packages.toPythonModule
          self.packages.x86_64-linux.default;
        default = pkgs.callPackage (import ./default.nix) { };
      });
    };
}
