/*
 * Under universal no-op free semantics, every free call is safe because free
 * never deallocates or dereferences its argument.  The interior pointer and
 * forged address exercise arguments that ordinary C allocators would reject.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int *p = malloc(2 * sizeof(*p));
    p[0] = 19;
    p[1] = 23;
    free(p + 1);
    free((void *)1);
    printf("interior-free-noop: sum=%d\n", p[0] + p[1]);
    return 0;
}
