# EACopy vcpkg Registry

This repository provides a vcpkg registry for EACopy, allowing other projects to easily consume EACopy as a dependency through vcpkg.

## Usage

### 1. Configure vcpkg Registry

Add the following to your project's `vcpkg-configuration.json`:

```json
{
  "registries": [
    {
      "kind": "git",
      "repository": "https://github.com/loonghao/EACopy",
      "reference": "add-vcpkg-registry-support",
      "packages": ["eacopy"]
    }
  ]
}
```

### 2. Add EACopy Dependency

Add EACopy to your project's `vcpkg.json`:

```json
{
  "name": "your-project",
  "version": "1.0.0",
  "dependencies": [
    "eacopy"
  ]
}
```

### 3. Install Dependencies

```bash
vcpkg install
```

### 4. Use in CMake

```cmake
find_package(EACopy CONFIG REQUIRED)
target_link_libraries(your_target PRIVATE EACopy::EACopyLib)
```

## Example Project Structure

```
your-project/
├── CMakeLists.txt
├── vcpkg.json
├── vcpkg-configuration.json
└── src/
    └── main.cpp
```

### Example CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.15)
project(YourProject)

find_package(EACopy CONFIG REQUIRED)

add_executable(your_app src/main.cpp)
target_link_libraries(your_app PRIVATE EACopy::EACopyLib)
```

### Example main.cpp

```cpp
#include <iostream>
// Include EACopy headers as needed
// #include "EACopyClient.h"

int main() {
    std::cout << "Using EACopy library!" << std::endl;
    return 0;
}
```

## Features

- **High-performance file copying**: Optimized for large file operations
- **Delta compression**: Efficient handling of file differences
- **Network acceleration**: Built-in server/client architecture
- **Cross-platform**: Primary support for Windows

## Registry Structure

```
ports/
└── eacopy/
    ├── portfile.cmake
    ├── vcpkg.json
    └── usage
versions/
├── baseline.json
└── e-/
    └── eacopy.json
```

## Continuous Integration

The registry includes automated testing through GitHub Actions to ensure:
- Port builds successfully
- Dependencies are correctly resolved
- Integration with consumer projects works

## Contributing

When updating the EACopy library:

1. Update version in `CMakeLists.txt`
2. Update version in `ports/eacopy/vcpkg.json`
3. Update version in `versions/e-/eacopy.json`
4. Update baseline in `versions/baseline.json`
5. Test the registry with the CI workflow

## License

EACopy is licensed under the BSD-3-Clause License. See [LICENSE](LICENSE) for details.
