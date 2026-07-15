/* Arithmetic integrity: adding UINTPTR_MAX to an interior pointer is not a
   valid in-object displacement.  Machine-width modular addition may wrap the
   numeric address to the preceding byte, which happens to lie within this
   allocation, but that in-bounds result cannot authorize a derivation whose
   unwrapped sum overflowed.  This makes the case useful for checking that
   pointer arithmetic is validated before wraparound erases the invalid
   offset, rather than merely bounds-checking the final numeric address. */
#include <stdint.h>
#include <stdlib.h>

int main(void)
{
    char *p = malloc(16);
    char *middle = p + 8;
    char *wrapped = middle + UINTPTR_MAX;
    volatile char value = *wrapped;
    (void)value;
    return 0;
}
