#include <stdlib.h>

int main(void) {
    int *old = malloc(sizeof(int));
    if (!old)
        return 0;
    *old = 7;
    int *grown = realloc(old, 2 * sizeof(int));
    if (!grown)
        return 0;
    grown[1] = grown[0] + 1;
    free(grown);
    return 0;
}
