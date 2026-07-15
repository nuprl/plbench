/* This access is unsafe even though the integer arithmetic produces a numeric
   address inside p's live allocation: converting that computed integer back
   to a pointer does not preserve the pointer's origin or its association with
   the allocation. Dereferencing forged must therefore produce a checked
   failure. This distinction is interesting because address-range checks alone
   would accept the access, while provenance-aware checking rejects a pointer
   that did not arise through valid pointer operations on the live object. */
#include <stdint.h>
#include <stdlib.h>

int main(void)
{
    char *p = malloc(16);
    uintptr_t raw = (uintptr_t)p + 7;
    char *forged = (char *)raw;
    volatile char value = *forged;
    (void)value;
    return 0;
}
