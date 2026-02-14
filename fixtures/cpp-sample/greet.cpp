#include "greet.h"

std::string greet(const std::string& name) {
    if (name.empty()) {
        return "Hello, World!";
    }
    return "Hello, " + name + "!";
}
