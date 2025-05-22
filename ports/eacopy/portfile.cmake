# EACopy vcpkg portfile

# Option 1: Use pre-built binaries from GitHub Releases (faster, recommended)
if(VCPKG_TARGET_IS_WINDOWS)
    set(VCPKG_POLICY_EMPTY_PACKAGE enabled)

    # Download pre-built binaries from GitHub Releases
    vcpkg_download_distfile(
        ARCHIVE
        URLS "https://github.com/loonghao/EACopy/releases/download/v${VERSION}/eacopy-${VERSION}-windows.zip"
        FILENAME "eacopy-${VERSION}-windows.zip"
        SHA512 "to-be-filled-after-release"
    )

    # Extract the archive
    vcpkg_extract_source_archive(
        SOURCE_PATH
        ARCHIVE "${ARCHIVE}"
        NO_REMOVE_ONE_LEVEL
    )

    # Install binaries
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        set(ARCH_DIR "${SOURCE_PATH}/${VERSION}/x64-windows")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(ARCH_DIR "${SOURCE_PATH}/${VERSION}/x86-windows")
    else()
        message(FATAL_ERROR "Unsupported architecture: ${VCPKG_TARGET_ARCHITECTURE}")
    endif()

    # Install include files
    file(INSTALL "${ARCH_DIR}/include/eacopy/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/eacopy")

    # Install libraries
    file(GLOB LIB_FILES "${ARCH_DIR}/lib/*.lib")
    if(LIB_FILES)
        file(INSTALL ${LIB_FILES} DESTINATION "${CURRENT_PACKAGES_DIR}/lib")
    endif()

    # Install tools
    file(GLOB TOOL_FILES "${ARCH_DIR}/bin/*.exe")
    if(TOOL_FILES)
        file(INSTALL ${TOOL_FILES} DESTINATION "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
    endif()

    # Install DLLs if any
    file(GLOB DLL_FILES "${ARCH_DIR}/bin/*.dll")
    if(DLL_FILES)
        file(INSTALL ${DLL_FILES} DESTINATION "${CURRENT_PACKAGES_DIR}/bin")
    endif()

    # Handle copyright
    file(INSTALL "${SOURCE_PATH}/${VERSION}/README.md" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)

else()
    # Option 2: Build from source for non-Windows platforms
    vcpkg_from_git(
        OUT_SOURCE_PATH SOURCE_PATH
        URL https://github.com/loonghao/EACopy.git
        REF 2f93a65e80f31be22dc2859fd28c25dbc2721ee6
        FETCH_REF v${VERSION}
        HEAD_REF master
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
endif()

# Configure usage
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
