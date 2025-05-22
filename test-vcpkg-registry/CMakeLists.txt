cmake_minimum_required(VERSION 3.15)
project(TestEACopyRegistry)

find_package(EACopy CONFIG REQUIRED)

add_executable(test_eacopy main.cpp)
target_link_libraries(test_eacopy PRIVATE EACopy::EACopyLib)
