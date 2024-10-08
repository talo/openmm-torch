#---------------------------------------------------
# OpenMM PyTorch Plugin
#----------------------------------------------------

CMAKE_MINIMUM_REQUIRED(VERSION 3.29.2) # CMake version on nix search as of 16-9-2024

# We need to know where OpenMM is installed so we can access the headers and libraries.
#SET(OPENMM_DIR $ENV{OPENMM_HOME} "Where OpenMM is installed")
INCLUDE_DIRECTORIES("${OPENMM_DIR}/include")
LINK_DIRECTORIES("${OPENMM_DIR}/lib" "${OPENMM_DIR}/lib/plugins")

# We need to know where LibTorch is installed so we can access the headers and libraries.
SET(PYTORCH_DIR "" CACHE PATH "Where the PyTorch C++ API is installed")
SET(CMAKE_PREFIX_PATH "${PYTORCH_DIR}")
FIND_PACKAGE(Torch REQUIRED)

# Specify the C++ version we are building for.
SET(CMAKE_CXX_STANDARD 17)
# Dual ABI
SET(GLIBCXX_USE_CXX11_ABI 1)

# Set flags for linking on mac
IF(APPLE)
    SET (CMAKE_INSTALL_NAME_DIR "@rpath")
    SET(EXTRA_COMPILE_FLAGS "-msse2 -stdlib=libc++")
ENDIF(APPLE)

# Select where to install
IF(${CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT})
    IF(WIN32)
        SET(CMAKE_INSTALL_PREFIX "$ENV{ProgramFiles}/OpenMM" CACHE PATH "Where to install the plugin" FORCE)
    ELSE(WIN32)
        SET(CMAKE_INSTALL_PREFIX "/usr/local/openmm" CACHE PATH "Where to install the plugin" FORCE)
    ENDIF(WIN32)
ENDIF(${CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT})

# Put all the tests and libraries in a single output directory.
IF(NOT EXECUTABLE_OUTPUT_PATH)
    SET(EXECUTABLE_OUTPUT_PATH ${PROJECT_BINARY_DIR}
            CACHE INTERNAL "Single output directory for building all executables.")
ENDIF()
IF(NOT LIBRARY_OUTPUT_PATH)
    SET(LIBRARY_OUTPUT_PATH ${PROJECT_BINARY_DIR}
            CACHE INTERNAL "Single output directory for building all libraries.")
ENDIF()
SET(${PROJECT_NAME}_EXECUTABLE_DIR ${EXECUTABLE_OUTPUT_PATH}/${CMAKE_CFG_INTDIR})
SET(${PROJECT_NAME}_LIBRARY_DIR    ${LIBRARY_OUTPUT_PATH}/${CMAKE_CFG_INTDIR})

# The source is organized into subdirectories, but we handle them all from
# this CMakeLists file rather than letting CMake visit them as SUBDIRS.
SET(NN_PLUGIN_SOURCE_SUBDIRS openmmapi serialization)

# Set the library name
SET(NN_LIBRARY_NAME OpenMMTorch)
SET(SHARED_NN_TARGET ${NN_LIBRARY_NAME})

# These are all the places to search for header files which are to be part of the API.
SET(API_INCLUDE_DIRS "openmmapi/include" "openmmapi/include/internal")

# Locate header files.
SET(API_INCLUDE_FILES)
FOREACH(dir ${API_INCLUDE_DIRS})
    FILE(GLOB fullpaths ${dir}/*.h)
    SET(API_INCLUDE_FILES ${API_INCLUDE_FILES} ${fullpaths})
ENDFOREACH(dir)

# Collect up source files
SET(SOURCE_FILES) # empty
SET(SOURCE_INCLUDE_FILES)
FOREACH(subdir ${NN_PLUGIN_SOURCE_SUBDIRS})
    FILE(GLOB src_files  ${CMAKE_CURRENT_SOURCE_DIR}/${subdir}/src/*.cpp)
    FILE(GLOB incl_files ${CMAKE_CURRENT_SOURCE_DIR}/${subdir}/src/*.h)
    SET(SOURCE_FILES         ${SOURCE_FILES}         ${src_files})   #append
    SET(SOURCE_INCLUDE_FILES ${SOURCE_INCLUDE_FILES} ${incl_files})

    ## Make sure we find these locally before looking in OpenMM/include if
    ## OpenMM was previously installed there.
    INCLUDE_DIRECTORIES(BEFORE ${CMAKE_CURRENT_SOURCE_DIR}/${subdir}/include)
ENDFOREACH(subdir)

# Create the library.
ADD_LIBRARY(${SHARED_NN_TARGET} SHARED ${SOURCE_FILES} ${SOURCE_INCLUDE_FILES} ${API_INCLUDE_FILES})
SET_TARGET_PROPERTIES(${SHARED_NN_TARGET}
        PROPERTIES COMPILE_FLAGS "-DNN_BUILDING_SHARED_LIBRARY ${EXTRA_COMPILE_FLAGS}"
        LINK_FLAGS "${EXTRA_COMPILE_FLAGS}")
TARGET_LINK_LIBRARIES(${SHARED_NN_TARGET} OpenMM)
TARGET_LINK_LIBRARIES(${SHARED_NN_TARGET} "${TORCH_LIBRARIES}")
INSTALL_TARGETS(/lib RUNTIME_DIRECTORY /lib ${SHARED_NN_TARGET})

# Install headers
FILE(GLOB API_ONLY_INCLUDE_FILES "openmmapi/include/*.h")
INSTALL (FILES ${API_ONLY_INCLUDE_FILES} DESTINATION include)
FILE(GLOB API_ONLY_INCLUDE_FILES_INTERNAL "openmmapi/include/internal/*.h")
INSTALL (FILES ${API_ONLY_INCLUDE_FILES_INTERNAL} DESTINATION include/internal)

# Enable testing
ENABLE_TESTING()
ADD_SUBDIRECTORY(serialization/tests)

# Copy test files to the build directory.
file(GLOB_RECURSE TEST_FILES RELATIVE "${CMAKE_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/tests/*.pt"
)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/tests)
set(COPIED_TEST_FILES)
foreach(TEST_FILE ${TEST_FILES})
    set(infile "${CMAKE_SOURCE_DIR}/${TEST_FILE}")
    set(outfile "${CMAKE_BINARY_DIR}/${TEST_FILE}")
    add_custom_command(
            OUTPUT "${outfile}"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${infile}" "${outfile}"
            DEPENDS "${infile}"
            COMMENT "CMake-copying file ${infile} to ${outfile}")
    set(COPIED_TEST_FILES ${COPIED_TEST_FILES} "${outfile}")
endforeach()
add_custom_target(CopyTestFiles ALL DEPENDS ${COPIED_TEST_FILES})

# Build the implementations for different platforms
ADD_SUBDIRECTORY(platforms/reference)

SET(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}")
IF(DEFINED BUILD_WITH_OPENCL)
    FIND_PACKAGE(OpenCL QUIET)
    IF(OPENCL_FOUND)
        SET(NN_BUILD_OPENCL_LIB ON CACHE BOOL "Build implementation for OpenCL")
    ELSE(OPENCL_FOUND)
        SET(NN_BUILD_OPENCL_LIB OFF CACHE BOOL "Build implementation for OpenCL")
    ENDIF(OPENCL_FOUND)
    IF(NN_BUILD_OPENCL_LIB)
        ADD_SUBDIRECTORY(platforms/opencl)
    ENDIF(NN_BUILD_OPENCL_LIB)
ENDIF(DEFINED BUILD_WITH_OPENCL)

FIND_PACKAGE(CUDA QUIET)
IF(CUDA_FOUND)
    SET(NN_BUILD_CUDA_LIB ON CACHE BOOL "Build implementation for CUDA")
ELSE(CUDA_FOUND)
    SET(NN_BUILD_CUDA_LIB OFF CACHE BOOL "Build implementation for CUDA")
ENDIF(CUDA_FOUND)
IF(NN_BUILD_CUDA_LIB)
    ADD_SUBDIRECTORY(platforms/cuda)
ENDIF(NN_BUILD_CUDA_LIB)

# Build the Python API
FIND_PROGRAM(PYTHON_EXECUTABLE python)
FIND_PROGRAM(SWIG_EXECUTABLE swig)
IF(PYTHON_EXECUTABLE AND SWIG_EXECUTABLE)
    SET(NN_BUILD_PYTHON_WRAPPERS ON CACHE BOOL "Build wrappers for Python")
ELSE(PYTHON_EXECUTABLE AND SWIG_EXECUTABLE)
    SET(NN_BUILD_PYTHON_WRAPPERS OFF CACHE BOOL "Build wrappers for Python")
ENDIF(PYTHON_EXECUTABLE AND SWIG_EXECUTABLE)
IF(NN_BUILD_PYTHON_WRAPPERS)
    ADD_SUBDIRECTORY(python)
ENDIF(NN_BUILD_PYTHON_WRAPPERS)
