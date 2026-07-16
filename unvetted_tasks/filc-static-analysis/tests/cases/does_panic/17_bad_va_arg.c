#include <stdarg.h>

static int read_pointer(int ignored, ...) {
    va_list arguments;
    int *pointer;
    int result;

    va_start(arguments, ignored);
    pointer = va_arg(arguments, int *);
    result = *pointer;
    va_end(arguments);
    return result;
}

int main(void) {
    return read_pointer(0, 123);
}
