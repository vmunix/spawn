cmake_minimum_required(VERSION 3.20)
project(cpp-sample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(greet greet.cpp)

add_executable(cpp-sample main.cpp)
target_link_libraries(cpp-sample PRIVATE greet)

enable_testing()
add_executable(cpp-sample-test main_test.cpp)
target_link_libraries(cpp-sample-test PRIVATE greet)
add_test(NAME cpp-sample-test COMMAND cpp-sample-test)
