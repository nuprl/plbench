/*
 * Safe because this task defines free as a no-op, so repeated frees neither
 * invalidate p nor release its storage. This distinctly tests double-free
 * behavior together with a subsequent read through the same pointer.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int *p = malloc(sizeof(*p));
    *p = 42;
    free(p);
    free(p);
    printf("double-free-noop: value=%d\n", *p);
    return 0;
}
