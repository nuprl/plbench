#include <stdlib.h>

int main(void) {
    char *memory = malloc(16);
    if (!memory)
        return 0;
    char *end = memory + 16;
    volatile char value = *end;
    (void)value;
    return 0;
}
