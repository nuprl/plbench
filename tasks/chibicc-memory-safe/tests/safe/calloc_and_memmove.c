/*
 * Safe: calloc creates six initialized bytes; every access stays within them,
 * memmove permits the overlapping [0,4) to [1,5) copy, and the block is freed
 * exactly once. This distinctly tests zero-initialization plus overlap-safe
 * library copying, behavior that an otherwise similar memcpy test cannot cover.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    unsigned char *bytes = calloc(6, 1);
    int zero = bytes[0] == 0 && bytes[5] == 0;
    bytes[0] = 10;
    bytes[1] = 20;
    bytes[2] = 30;
    bytes[3] = 40;
    memmove(bytes + 1, bytes, 4);
    printf("calloc-memmove: zero=%d data=%u,%u,%u,%u,%u\n",
           zero, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4]);
    int ok = zero && bytes[0] == 10 && bytes[1] == 10 && bytes[4] == 40;
    free(bytes);
    return ok ? 0 : 1;
}
