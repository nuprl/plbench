/*
 * Safe: both heap objects are eight bytes, and memset, memcpy, and the two
 * indexed reads stay within those bounds; freeing their base pointers is also
 * permitted (and is a no-op under the task semantics).  This distinctly tests
 * valid bulk-library accesses, rather than only ordinary scalar loads/stores.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    char *src = malloc(8);
    char *dst = malloc(8);
    memset(src, 0x2a, 8);
    memcpy(dst, src, 8);
    int ok = dst[0] == 0x2a && dst[7] == 0x2a;
    printf("bulk: first=%d last=%d bytes=%d\n", dst[0], dst[7], 8);
    free(src);
    free(dst);
    return ok ? 0 : 1;
}
