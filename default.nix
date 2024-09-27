{ gcc13Stdenv, cudaPackages, python311, python311Packages, openmm, libtorch-bin
, cmake, addOpenGLRunpath, swig4 }:
let
  buildDependencies = [ cmake cudaPackages.cudatoolkit addOpenGLRunpath ];
  omm = openmm.override { enableCuda = true; };
  cppDependencies =
    [ libtorch-bin openmm swig4 cudaPackages.cudatoolkit python311 ];
  projectName = "openmmtorch";
  overlay = final: prev: {
    python311Packages = prev.python311Packages {
      torch = prev.python311Packages.torch.overrideAttrs (oldAttrs: rec {
        cmakeFlags = (oldAttrs.cmakeFlags or [ ])
          ++ [ "-DGLIBCXX_USE_CXX11_ABI=1" ];
      });
    };
  };
in gcc13Stdenv.mkDerivation {
  name = projectName;
  version = "1.4";
  src = ./.;
  overlays = [ overlay ];
  nativeBuildInputs = buildDependencies;
  buildInputs = cppDependencies;
  OPENMM_HOME = omm;
  cmakeFlags = [ "-DTORCH_CUDA_ARCH_LIST=8.0" "-DOPENMM_DIR=${omm}" ];
  preConfigure = ''
    export OPENMM_HOME=${omm}
  '';
  propagatedBuildInputs = [
    (openmm.override { enableCuda = true; })
    python311Packages.setuptools
    python311Packages.wheel
    python311Packages.build
    python311Packages.pip
    python311Packages.openmm
    python311Packages.torch
  ];
  postInstall = ''
    cd python
    # We want to add each of the directories in the torch includes to the include path
    TORCH_INCS_DIR=${libtorch-bin.dev}/include
    TORCH_INCS=""
    for dir in $TORCH_INCS_DIR/*; do
      TORCH_INCS="$TORCH_INCS -I$dir"
    done

    swig -includeall -python -c++ -o TorchPluginWrapper.cpp "-I${openmm}/include" $TORCH_INCS ${
      ./python/openmmtorch.i
    }
    ${python311Packages.python.pythonOnBuildForHost.interpreter} -m build --wheel --outdir dist
    ${python311Packages.python.pythonOnBuildForHost.interpreter} -m pip install --prefix=$out dist/*.whl

  '';
  postFixup = ''
    addOpenGLRunpath $out/lib/plugins/*.so
    addOpenGLRunpath $out/lib/*.so

    for lib in $out/lib/python3.11/site-packages/*.so; do
      echo "Adding rpath to $lib"
      addOpenGLRunpath "$lib"
    done
  '';
}
