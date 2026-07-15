/*
 * &pair.x and &pair.y are separate, in-bounds pointers to live members, so
 * each dereference stays within its own subobject. Passing them through a
 * call checks that their subobject bounds and liveness survive the call.
 */
#include <stdio.h>

struct Pair { int x; int y; };

static int add(int *p, int *q) { return *p + *q; }

int main(void) {
    struct Pair pair = { 19, 23 };
    int result = add(&pair.x, &pair.y);
    printf("subobjects: %d + %d = %d\n", pair.x, pair.y, result);
    return result == 42 ? 0 : 1;
}
