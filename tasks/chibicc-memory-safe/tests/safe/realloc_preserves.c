/* Safe: realloc preserves the initialized prefix, and the returned pointer
 * alone is used within its expanded allocation.  Prefix preservation plus
 * wider bounds on this distinct result exercises both realloc guarantees. */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    unsigned char *p = malloc(4);
    p[0] = 11;
    p[3] = 31;
    p = realloc(p, 16);
    if (!p || p[0] != 11 || p[3] != 31)
        return 1;
    p[15] = 9;
    printf("realloc: prefix=%u,%u tail=%u size=%d\n",
           p[0], p[3], p[15], 16);
    free(p);
    return 0;
}
