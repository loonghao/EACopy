// (c) Electronic Arts. All Rights Reserved.
#pragma once

// Central management of all third-party dependencies
// This allows other files to include this header instead of directly referencing third-party library paths

// ZSTD - using vcpkg
#include <zstd.h>

// LZMA - using vcpkg
#include <lzma.h>

// XDELTA - still using local source
#include "../external/xdelta/xdelta3/xdelta3.h"
