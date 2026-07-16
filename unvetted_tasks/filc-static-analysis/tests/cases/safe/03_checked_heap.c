#include <stdlib.h>

int main(void) {
    int *values = malloc(8 * sizeof(int));
    if (!values)
        return 0;
    for (int i = 0; i < 8; ++i)
        values[i] = i;
    free(values);
    return 0;
}
