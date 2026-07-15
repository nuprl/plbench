/*
 * This program is safe because the heap object and its function-pointer field
 * remain live, and the stored pointer designates a defined function with the
 * matching type. It checks that function pointers survive storage in ordinary
 * memory and can later be loaded and called indirectly.
 */
#include <stdio.h>
#include <stdlib.h>

typedef int (*Unary)(int);

struct Dispatch {
    Unary function;
    int argument;
};

static int triple(int value) {
    return value * 3;
}

int main(void) {
    struct Dispatch *dispatch = malloc(sizeof(*dispatch));
    dispatch->function = triple;
    dispatch->argument = 14;
    printf("function-object: result=%d\n",
           dispatch->function(dispatch->argument));
    return 0;
}
