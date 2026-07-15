/* Writing the union's integer member records only an integer value, even when
   that value came from a pointer. Reading the inactive pointer member does not
   turn those bits back into a pointer that is safe to dereference. This case is
   important because union type-punning is another route for forging pointers,
   beyond the more obvious path through explicit pointer casts. */
#include <stdint.h>
#include <stdlib.h>

union bits_or_pointer {
    uintptr_t bits;
    int *pointer;
};

int main(void) {
    int *p = malloc(sizeof(*p));
    union bits_or_pointer u;
    u.bits = (uintptr_t)p;
    volatile int value = *u.pointer;
    (void)value;
    return 0;
}
