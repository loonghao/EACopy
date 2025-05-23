#-------------------------------------------------------------------------------------------
# Copyright (C) Electronic Arts Inc.  All rights reserved.
#-------------------------------------------------------------------------------------------
# Note: This CMakeLists.txt has been modified to support vcpkg integration
#-------------------------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.15)

# Set CMake policy version for compatibility
if(POLICY CMP0048)
  cmake_policy(SET CMP0048 NEW)  # project() command manages VERSION variables
endif()
if(POLICY CMP0077)
  cmake_policy(SET CMP0077 NEW)  # option() honors normal variables
endif()
if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)  # MSVC runtime library flags
endif()
if(POLICY CMP0074)
  cmake_policy(SET CMP0074 NEW)  # find_package uses <PackageName>_ROOT variables
endif()

project(EACopy VERSION 1.20.0 LANGUAGES CXX)

# NOTE: Only used in multi-configuration environments
set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "My multi config types" FORCE)

#-------------------------------------------------------------------------------------------
# Options
#-------------------------------------------------------------------------------------------
option(EACOPY_BUILD_TESTS "Enable generation of build files for tests" OFF)
option(EACOPY_BUILD_AS_LIBRARY "Build EACopy as a library for use in other projects" ON)
option(EACOPY_INSTALL "Install EACopy library and headers" ON)

if (WIN32)
    SET(CMAKE_CXX_FLAGS "/GR-")

    # Add Windows-specific compile options
    add_compile_options(
        /W3     # Warning level 3
        /MP     # Multi-processor compilation
        /wd4244 # Disable warning C4244: conversion from 'double' to 'float'
        /wd4267 # Disable warning C4267: conversion from 'size_t' to 'int'
        /wd4305 # Disable warning C4305: truncation from 'double' to 'float'
        /bigobj # Support for large object files
    )

    # Use dynamic runtime library (MD/MDd) instead of static (MT/MTd)
    # This is critical for compatibility with Python extensions
    foreach(flag_var
        CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
        CMAKE_C_FLAGS CMAKE_C_FLAGS_DEBUG CMAKE_C_FLAGS_RELEASE)
        if(${flag_var} MATCHES "/MT")
            string(REGEX REPLACE "/MT" "/MD" ${flag_var} "${${flag_var}}")
        endif()
    endforeach()
endif(WIN32)

if (UNIX)
    find_package(Threads)
endif (UNIX)

#-------------------------------------------------------------------------------------------
# External dependencies using vcpkg
#-------------------------------------------------------------------------------------------
# Find required packages
find_package(zstd CONFIG REQUIRED)
find_package(LibLZMA REQUIRED)
find_package(xdelta CONFIG REQUIRED)

#-------------------------------------------------------------------------------------------
# Library definitions
#-------------------------------------------------------------------------------------------

# Set external libraries list
set(EACOPY_ZSTD_LIB zstd::libzstd)
set(EACOPY_LZMA_LIB LibLZMA::LibLZMA)
set(EACOPY_XDELTA_LIB xdelta::xdelta)

set(EACOPY_EXTERNAL_LIBS ${EACOPY_ZSTD_LIB} ${EACOPY_LZMA_LIB} ${EACOPY_XDELTA_LIB})

set(EACOPY_SHARED_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/include/EACopyNetwork.h
    ${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyNetwork.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/include/EACopyShared.h
    ${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyShared.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/source/Addition.manifest)

add_definitions(-DEACOPY_ALLOW_DELTA_COPY)

# Add xdelta required definitions for all targets
# Use CMake to determine the correct size_t size for the target architecture
include(CheckTypeSize)
check_type_size("size_t" SIZEOF_SIZE_T)
check_type_size("unsigned long long" SIZEOF_UNSIGNED_LONG_LONG)

add_compile_definitions(
    SIZEOF_SIZE_T=${SIZEOF_SIZE_T}
    SIZEOF_UNSIGNED_LONG_LONG=${SIZEOF_UNSIGNED_LONG_LONG}
    XD3_USE_LARGEFILE64=1
    SECONDARY_DJW=1
    SECONDARY_LZMA=1
    SECONDARY_FGK=1
    LZMA_API_STATIC
    _CRT_SECURE_NO_WARNINGS
)

# Note: _CRT_SECURE_NO_WARNINGS already defined above with xdelta definitions

if(WIN32)
    add_compile_definitions(
        _WIN32=1
        XD3_WIN32=1
    )
endif()

# Add delta copy files
set(EACOPY_SHARED_FILES
    ${EACOPY_SHARED_FILES}
    ${CMAKE_CURRENT_SOURCE_DIR}/include/EACopyDelta.h
    ${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyDelta.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyDeltaZstd.h
    ${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyDeltaXDelta.h)

add_executable(EACopy
    source/EACopy.cpp
    include/EACopyClient.h
    source/EACopyClient.cpp
    ${EACOPY_SHARED_FILES})

# Set include directories
set(EACOPY_INCLUDE_DIRS
    ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Add vcpkg include directories if available
if(DEFINED VCPKG_TARGET_TRIPLET)
    list(APPEND EACOPY_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}/include)
endif()

target_include_directories(EACopy PUBLIC ${EACOPY_INCLUDE_DIRS})

if (WIN32)
    target_link_libraries(EACopy ${EACOPY_EXTERNAL_LIBS})
endif(WIN32)

if (UNIX)
    target_link_libraries(EACopy ${EACOPY_EXTERNAL_LIBS} ${CMAKE_THREAD_LIBS_INIT})
endif (UNIX)

if (WIN32)
    add_executable(EACopyService
        source/EACopyService.cpp
        include/EACopyServer.h
        source/EACopyServer.cpp
        ${EACOPY_SHARED_FILES})

    target_include_directories(EACopyService PUBLIC ${EACOPY_INCLUDE_DIRS})
    target_link_libraries(EACopyService ${EACOPY_EXTERNAL_LIBS})
endif(WIN32)

if(EACOPY_BUILD_TESTS)
    include(CTest)
    add_subdirectory(test)
endif()

#-------------------------------------------------------------------------------------------
# Library target for integration with other projects
#-------------------------------------------------------------------------------------------
if(EACOPY_BUILD_AS_LIBRARY)
    # Create a static library target
    add_library(EACopyLib STATIC
        ${EACOPY_SHARED_FILES}
        include/EACopyClient.h
        source/EACopyClient.cpp
    )

    # Set include directories
    target_include_directories(EACopyLib PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    )

    # Link with dependencies
    if (WIN32)
        target_link_libraries(EACopyLib ${EACOPY_EXTERNAL_LIBS})
    endif(WIN32)

    if (UNIX)
        target_link_libraries(EACopyLib ${EACOPY_EXTERNAL_LIBS} ${CMAKE_THREAD_LIBS_INIT})
    endif (UNIX)

    # Set delta copy option (now enabled)
    set(EACOPY_ALLOW_DELTA_COPY ON CACHE BOOL "Enable delta copy functionality")

    # Add compile definitions
    target_compile_definitions(EACopyLib PUBLIC
            $<$<BOOL:${EACOPY_ALLOW_DELTA_COPY}>:EACOPY_ALLOW_DELTA_COPY>
            $<$<BOOL:${WIN32}>:NOMINMAX>
            $<$<BOOL:${WIN32}>:WIN32_LEAN_AND_MEAN>
        )

        # Add Windows-specific compile options for EACopyLib
        if(MSVC)
            target_compile_options(EACopyLib PRIVATE
                $<$<CONFIG:Debug>:/MDd>
                $<$<CONFIG:Release>:/MD>
            )
        endif()
endif()

#-------------------------------------------------------------------------------------------
# Installation rules
#-------------------------------------------------------------------------------------------
if(EACOPY_INSTALL)
    include(GNUInstallDirs)

    # Install headers
    install(DIRECTORY include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/eacopy
        FILES_MATCHING PATTERN "*.h"
    )

    if(EACOPY_BUILD_AS_LIBRARY)
        # Install main library
        install(TARGETS EACopyLib
            EXPORT EACopyTargets
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
        )

        # Install CMake configuration files
        install(EXPORT EACopyTargets
            FILE EACopyTargets.cmake
            NAMESPACE EACopy::
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EACopy
        )

        # Create and install config file
        include(CMakePackageConfigHelpers)
        configure_package_config_file(
            ${CMAKE_CURRENT_SOURCE_DIR}/cmake/EACopyConfig.cmake.in
            ${CMAKE_CURRENT_BINARY_DIR}/EACopyConfig.cmake
            INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EACopy
        )

        # Install config file
        install(FILES
            ${CMAKE_CURRENT_BINARY_DIR}/EACopyConfig.cmake
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/EACopy
        )
    endif()
endif()
