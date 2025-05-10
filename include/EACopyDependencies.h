// (c) Electronic Arts. All Rights Reserved.
#pragma once

// Central management of all third-party dependencies
// This allows other files to include this header instead of directly referencing third-party library paths

// ZSTD
#ifdef EACOPY_USE_SYSTEM_ZSTD
    #include <zstd.h>
#else
    #include "../external/zstd/lib/zstd.h"
#endif

// LZMA
#ifdef EACOPY_USE_SYSTEM_LZMA
    #include <lzma.h>
#else
    #include "../external/lzma/liblzma/api/lzma.h"
#endif

// XDELTA
#ifdef EACOPY_USE_SYSTEM_XDELTA
    #include <xdelta3.h>
#else
    #include "../external/xdelta/xdelta3/xdelta3.h"
#endif
