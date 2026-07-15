/* Under this task's non-destructive realloc semantics, resizing preserves the
 * old allocation and returns a distinct live allocation, so both old and new
 * may be accessed. realloc(old, 0) likewise returns NULL without freeing old;
 * checking distinctness and preserved aliases exercises these guarantees.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int *old = malloc(sizeof(*old));
    *old = 17;
    int *replacement = realloc(old, 2 * sizeof(*replacement));
    if (!replacement)
        return 1;
    replacement[0] = 25;
    void *zero = realloc(old, 0);
    printf("realloc-alias: old=%d new=%d distinct=%d zero-null=%d\n",
           *old, replacement[0], old != replacement, zero == NULL);
    return 0;
}
