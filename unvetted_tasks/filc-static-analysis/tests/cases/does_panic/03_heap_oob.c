#include <stdlib.h>

int main(void) {
    volatile char *memory = malloc(16);
    if (!memory)
        return 0;
    memory[16] = 9;
    return 0;
}
