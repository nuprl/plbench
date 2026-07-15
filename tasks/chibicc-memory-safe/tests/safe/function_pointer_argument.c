/*
 * This program is safe because apply receives a pointer to a defined function
 * with the exact expected type and invokes it with valid integer arguments.
 * It checks function pointers passed through call parameters, independently of
 * storing them in an aggregate or heap object.
 */
#include <stdio.h>

typedef int (*Binary)(int, int);

static int add(int left, int right) {
    return left + right;
}

static int apply(Binary function, int left, int right) {
    return function(left, right);
}

int main(void) {
    printf("function-argument: result=%d\n", apply(add, 19, 23));
    return 0;
}
