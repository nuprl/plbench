/* Safe: p owns four allocated ints, q is an interior alias to the third,
   and every access stays within that live allocation before it is freed.
   This exercises tracking heap bounds through pointer arithmetic and aliases. */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    int *p = malloc(4 * sizeof(*p));
    int *q = p + 2;
    p[0] = 7;
    *q = 35;
    int result = p[0] + p[2];
    printf("heap-alias: %d + %d = %d\n", p[0], *q, result);
    free(p);
    return result == 42 ? 0 : 1;
}
