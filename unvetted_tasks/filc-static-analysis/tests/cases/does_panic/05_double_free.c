#include <stdlib.h>

int main(void) {
    void *memory = malloc(32);
    if (!memory)
        return 0;
    free(memory);
    free(memory);
    return 0;
}
