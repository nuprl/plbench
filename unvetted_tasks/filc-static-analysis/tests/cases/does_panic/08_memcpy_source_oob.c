#include <stdlib.h>
#include <string.h>

int main(void) {
    char *source = malloc(16);
    char *destination = malloc(16);
    if (!source || !destination)
        return 0;
    memcpy(destination, source, 17);
    return destination[0];
}
