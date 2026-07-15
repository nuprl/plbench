/* This nine-byte memcpy is unsafe at both ends: src contains only an
   eight-byte readable range, and dst contains only an eight-byte writable
   range, so the operation would read one byte past src and write one byte past
   dst. Checked library boundaries are interesting because a bulk operation
   crosses both allocation boundaries inside libc rather than through explicit
   source-level loads and stores, and therefore must be rejected before any
   copying occurs. */
#include <stdlib.h>
#include <string.h>

int main(void)
{
    char *src = malloc(8);
    char *dst = malloc(8);
    memcpy(dst, src, 9);
    return 0;
}
