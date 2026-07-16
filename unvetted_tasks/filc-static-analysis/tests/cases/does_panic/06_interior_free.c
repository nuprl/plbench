#include <stdlib.h>

int main(void) {
    char *memory = malloc(16);
    if (!memory)
        return 0;
    free(memory + 1);
    return 0;
}
