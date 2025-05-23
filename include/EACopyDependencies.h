// (c) Electronic Arts. All Rights Reserved.
#pragma once

// Central management of all third-party dependencies
// This allows other files to include this header instead of directly referencing third-party library paths

// ZSTD - using vcpkg
#include <zstd.h>

// LZMA - using vcpkg
#include <lzma.h>

// XDELTA - using vcpkg, only include when delta copy is enabled
#if defined(EACOPY_ALLOW_DELTA_COPY)
#include <xdelta3/xdelta3.h>
#endif
