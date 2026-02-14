#include "greet.h"
#include <cassert>
#include <iostream>

int main() {
    assert(greet("") == "Hello, World!");
    assert(greet("C++") == "Hello, C++!");
    std::cout << "All tests passed" << std::endl;
    return 0;
}
