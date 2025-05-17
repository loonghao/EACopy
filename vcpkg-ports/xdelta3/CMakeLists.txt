cmake_minimum_required(VERSION 3.15)
project(xdelta3 C)

option(XDELTA3_USE_LIBLZMA "Use liblzma for LZMA compression" ON)

# Find dependencies
if(XDELTA3_USE_LIBLZMA)
    find_package(LibLZMA REQUIRED)
endif()

# Define source files
set(XDELTA3_SOURCES
    xdelta3/xdelta3.c
)

set(XDELTA3_HEADERS
    xdelta3/xdelta3.h
    xdelta3/xdelta3-blkcache.h
    xdelta3/xdelta3-cfgs.h
    xdelta3/xdelta3-decode.h
    xdelta3/xdelta3-djw.h
    xdelta3/xdelta3-fgk.h
    xdelta3/xdelta3-hash.h
    xdelta3/xdelta3-internal.h
    xdelta3/xdelta3-list.h
    xdelta3/xdelta3-lzma.h
    xdelta3/xdelta3-main.h
    xdelta3/xdelta3-merge.h
    xdelta3/xdelta3-second.h
    xdelta3/xdelta3-test.h
)

# Add library
add_library(xdelta3 ${XDELTA3_SOURCES} ${XDELTA3_HEADERS})

# Set compile definitions
target_compile_definitions(xdelta3 PRIVATE
    SIZEOF_SIZE_T=8
    SIZEOF_UNSIGNED_LONG_LONG=8
    XD3_USE_LARGEFILE64=1
    SECONDARY_DJW=1
    SECONDARY_FGK=1
    LZMA_API_STATIC
)

if(XDELTA3_USE_LIBLZMA)
    target_compile_definitions(xdelta3 PRIVATE SECONDARY_LZMA=1)
endif()

if(WIN32)
    target_compile_definitions(xdelta3 PRIVATE _WIN32=1 XD3_WIN32=1)
endif()

# Set include directories
target_include_directories(xdelta3
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/xdelta3>
        $<INSTALL_INTERFACE:include>
)

# Link dependencies
if(XDELTA3_USE_LIBLZMA)
    target_link_libraries(xdelta3 PRIVATE LibLZMA::LibLZMA)
endif()

# Installation
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

install(
    TARGETS xdelta3
    EXPORT xdelta3-targets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(
    FILES ${XDELTA3_HEADERS}
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/xdelta3
)

# Export targets
install(
    EXPORT xdelta3-targets
    FILE xdelta3-targets.cmake
    NAMESPACE xdelta3::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/xdelta3
)

# Create and install config file
configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/xdelta3-config.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/xdelta3-config.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/xdelta3
)

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/xdelta3-config.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/xdelta3
)
