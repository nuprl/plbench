/*
 * Safe because free is a no-op and the heap-stored pointer keeps its target
 * reachable to the GC.  Surviving a forced collection is interesting because
 * it verifies that a heap alias, not a local variable, preserves the object.
 */
#include <stdio.h>
#include <stdlib.h>

void __safe_collect(void);

struct holder {
    int *target;
};

int main(void)
{
    struct holder *a = malloc(sizeof(*a));
    int *b = malloc(sizeof(*b));
    *b = 41;
    a->target = b;
    free(b);
    b = NULL;
    __safe_collect();
    ++*a->target;
    printf("free-alias-noop: value=%d retained=%d\n",
           *a->target, a->target != NULL);
    return 0;
}
