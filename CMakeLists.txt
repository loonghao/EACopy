#-------------------------------------------------------------------------------------------
# Copyright (C) Electronic Arts Inc.  All rights reserved.
#-------------------------------------------------------------------------------------------
# Note: This CMakeLists.txt has been modified to support integration with py-eacopy
# and other projects that use EACopy as a library.
#-------------------------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.10)
project(EACopy CXX)

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
	find_package (Threads)
endif (UNIX)


#-------------------------------------------------------------------------------------------
# External dependencies paths
#-------------------------------------------------------------------------------------------
set(EACOPY_EXTERNAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external")
set(EACOPY_ZSTD_DIR "${EACOPY_EXTERNAL_DIR}/zstd")
set(EACOPY_LZMA_DIR "${EACOPY_EXTERNAL_DIR}/lzma")
set(EACOPY_XDELTA_DIR "${EACOPY_EXTERNAL_DIR}/xdelta")

#-------------------------------------------------------------------------------------------
# Options for external dependencies
#-------------------------------------------------------------------------------------------
option(EACOPY_USE_SYSTEM_ZSTD "Use system zstd library instead of bundled one" OFF)
option(EACOPY_USE_SYSTEM_LZMA "Use system lzma library instead of bundled one" OFF)
option(EACOPY_USE_SYSTEM_XDELTA "Use system xdelta library instead of bundled one" OFF)

#-------------------------------------------------------------------------------------------
# Zstd
#-------------------------------------------------------------------------------------------
if(EACOPY_USE_SYSTEM_ZSTD)
    find_package(zstd REQUIRED)
    set(ZSTD_LIBRARIES zstd::zstd)
    add_library(libzstd_static ALIAS zstd::zstd)
else()
    set(ZSTD_BUILD_PROGRAMS OFF)
    set(ZSTD_BUILD_SHARED OFF)
    set(ZSTD_BUILD_TESTS OFF)
    set(ZSTD_STATIC_LINKING_ONLY ON)
    add_subdirectory(${EACOPY_ZSTD_DIR}/build/cmake)
    if (WIN32)
        target_compile_options(libzstd_static PUBLIC "$<$<CONFIG:RELEASE>:/Oi>")
    endif(WIN32)
endif()

#-------------------------------------------------------------------------------------------
# lzma
#-------------------------------------------------------------------------------------------
if(EACOPY_USE_SYSTEM_LZMA)
    find_package(LibLZMA REQUIRED)
    set(LZMA_LIBRARIES LibLZMA::LibLZMA)
    add_library(lzma ALIAS LibLZMA::LibLZMA)
else()
    add_subdirectory(${EACOPY_LZMA_DIR})
    if (WIN32)
        target_compile_options(lzma PUBLIC "$<$<CONFIG:RELEASE>:/Oi>")
    endif(WIN32)
endif()

#-------------------------------------------------------------------------------------------
# xdelta
#-------------------------------------------------------------------------------------------
if(EACOPY_USE_SYSTEM_XDELTA)
    find_package(xdelta REQUIRED)
    set(XDELTA_LIBRARIES xdelta::xdelta)
    add_library(xdelta ALIAS xdelta::xdelta)
else()
    add_compile_definitions(SIZEOF_SIZE_T=8 SIZEOF_UNSIGNED_LONG_LONG=8 XD3_USE_LARGEFILE64=1 SECONDARY_DJW=1 SECONDARY_LZMA=1 SECONDARY_FGK=1 LZMA_API_STATIC)
    if(WIN32)
        add_compile_definitions(_WIN32=1 XD3_WIN32=1)
    endif()
    add_subdirectory(${EACOPY_XDELTA_DIR})
    if(NOT EACOPY_USE_SYSTEM_LZMA)
        target_include_directories(xdelta PRIVATE ${EACOPY_LZMA_DIR}/liblzma/api)
    endif()
    if (WIN32)
        target_compile_options(xdelta PUBLIC "$<$<CONFIG:RELEASE>:/Oi>")
    endif(WIN32)
endif()

#-------------------------------------------------------------------------------------------
# Library definitions
#-------------------------------------------------------------------------------------------

# Set external libraries list
if(EACOPY_USE_SYSTEM_ZSTD)
    set(EACOPY_ZSTD_LIB ${ZSTD_LIBRARIES})
else()
    set(EACOPY_ZSTD_LIB libzstd_static)
endif()

if(EACOPY_USE_SYSTEM_LZMA)
    set(EACOPY_LZMA_LIB ${LZMA_LIBRARIES})
else()
    set(EACOPY_LZMA_LIB lzma)
endif()

if(EACOPY_USE_SYSTEM_XDELTA)
    set(EACOPY_XDELTA_LIB ${XDELTA_LIBRARIES})
else()
    set(EACOPY_XDELTA_LIB xdelta)
endif()

set(EACOPY_EXTERNAL_LIBS ${EACOPY_ZSTD_LIB} ${EACOPY_XDELTA_LIB} ${EACOPY_LZMA_LIB})

set(EACOPY_SHARED_FILES
	${CMAKE_CURRENT_SOURCE_DIR}/include/EACopyNetwork.h
	${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyNetwork.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/include/EACopyShared.h
	${CMAKE_CURRENT_SOURCE_DIR}/source/EACopyShared.cpp
	${CMAKE_CURRENT_SOURCE_DIR}/source/Addition.manifest)



add_definitions(-DEACOPY_ALLOW_DELTA_COPY)
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
set(EACOPY_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Add third-party library include directories
if(NOT EACOPY_USE_SYSTEM_ZSTD)
    list(APPEND EACOPY_INCLUDE_DIRS ${EACOPY_ZSTD_DIR}/lib)
endif()

if(NOT EACOPY_USE_SYSTEM_LZMA)
    list(APPEND EACOPY_INCLUDE_DIRS ${EACOPY_LZMA_DIR}/liblzma/api)
endif()

if(NOT EACOPY_USE_SYSTEM_XDELTA)
    list(APPEND EACOPY_INCLUDE_DIRS ${EACOPY_XDELTA_DIR}/xdelta3)
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

	# Add compile definitions
	target_compile_definitions(EACopyLib PUBLIC
			EACOPY_ALLOW_DELTA_COPY
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
		# Install library and dependencies
		if(NOT EACOPY_USE_SYSTEM_ZSTD)
			install(TARGETS libzstd_static
				EXPORT EACopyTargets
				LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
				ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
				RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
				INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
			)
		endif()

		if(NOT EACOPY_USE_SYSTEM_LZMA)
			install(TARGETS lzma
				EXPORT EACopyTargets
				LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
				ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
				RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
				INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
			)
		endif()

		if(NOT EACOPY_USE_SYSTEM_XDELTA)
			install(TARGETS xdelta
				EXPORT EACopyTargets
				LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
				ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
				RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
				INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
			)
		endif()

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
