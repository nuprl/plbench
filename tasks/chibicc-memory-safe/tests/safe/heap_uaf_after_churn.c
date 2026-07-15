/* With no-op free, p's allocation remains live, so dereferencing p is safe.
 * Allocation churn adds address-reuse pressure, making persistent alias validity
 * after many intervening malloc/free calls the behavior this test exercises. */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    enum { count = 512 };
    char *p = malloc(32);
    *p = 42;
    free(p);
    for (int i = 0; i < count; ++i) {
        char *q = malloc(32);
        *q = (char)i;
        free(q);
    }
    printf("free-churn-noop: value=%d iterations=%d\n", *p, count);
    return 0;
}
