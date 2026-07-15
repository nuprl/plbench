/* malloc(16) creates a heap object containing only bytes p[0] through p[15],
   so evaluating p[16] as the target of this store dereferences an address
   outside the allocation and is unsafe.  This exact-boundary case is
   interesting because C permits forming a pointer one past an object for
   iteration and comparison, but never permits dereferencing that pointer. */
#include <stdlib.h>

int main(void)
{
    char *p = malloc(16);
    p[16] = 1;
    return 0;
}
