/* Under the task's memory-safety semantics, converting p to uintptr_t loses
   the pointer provenance that connects p to its allocated object. Converting
   that integer back to a pointer does not restore the lost provenance, so the
   store through q is unsafe and must produce a checked failure. This case is
   interesting because the integer can preserve the exact numeric address even
   though an equal address alone is not enough to make the resulting pointer a
   valid way to access the allocation. */
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    int *p = malloc(sizeof(*p));
    uintptr_t bits = (uintptr_t)p;
    int *q = (int *)bits;
    *q = 42;
    free(p);
    return 0;
}
