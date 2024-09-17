{ cudaPackages, python311, python311Packages, openmm, libtorch-bin
, cmake, addOpenGLRunpath, swig4 }:
let
  buildDependencies = [ cmake cudaPackages.cudatoolkit addOpenGLRunpath ];
  cppDependencies =
    [ libtorch-bin openmm swig4 cudaPackages.cudatoolkit python311 ];
  projectName = "openmm-torch";
in stdenv.mkDerivation {
  name = projectName;
  version = "1.1.0";
  src = ./.;
  nativeBuildInputs = buildDependencies;
  buildInputs = cppDependencies;
  preConfigure = ''
    export OPENMM_HOME=${openmm.override { enableCuda = true; }}
  '';
  propagatedBuildInputs = [
    (openmm.override { enableCuda = true; })
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
    ${python311Packages.python.pythonForBuild.interpreter} setup.py build
    ${python311Packages.python.pythonForBuild.interpreter} setup.py install --prefix=$out
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