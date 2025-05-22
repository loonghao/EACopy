# EACopy vcpkg portfile
vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL https://github.com/loonghao/EACopy.git
    REF v${VERSION}
    HEAD_REF master
    PATCHES
        # Add any patches if needed
)

# Configure CMake
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DEACOPY_BUILD_TESTS=OFF
        -DEACOPY_BUILD_AS_LIBRARY=ON
        -DEACOPY_INSTALL=ON
)

# Build the project
vcpkg_cmake_build()

# Install the project
vcpkg_cmake_install()

# Remove debug includes (they are the same as release)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

# Handle copyright
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")

# Configure usage
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
