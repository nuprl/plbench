#include <stdint.h>
#include <stdlib.h>

int main(void) {
    char *memory = malloc(16);
    if (!memory)
        return 0;
    uintptr_t raw = (uintptr_t)memory + 7;
    char *forged = (char *)raw;
    volatile char value = *forged;
    (void)value;
    return 0;
}
