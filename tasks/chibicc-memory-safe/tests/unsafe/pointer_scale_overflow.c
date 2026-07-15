/* This allocation contains only one int, while the mathematical byte offset
   index * sizeof(int) is larger than SIZE_MAX, so p[index] is not a valid
   access.  On x86-64 the machine-size multiplication wraps that offset to
   zero, which could make a bounds check performed afterward mistake the
   access for p[0].  The case is therefore interesting because safety requires
   rejecting the oversized index before performing modular multiplication. */
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    int *p = malloc(sizeof(*p));
    size_t index = SIZE_MAX / sizeof(*p) + 1;
    volatile int value = p[index];
    (void)value;
    return 0;
}
