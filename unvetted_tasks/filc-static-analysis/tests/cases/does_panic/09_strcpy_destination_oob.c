#include <stdlib.h>
#include <string.h>

int main(void) {
    char *destination = malloc(16);
    if (!destination)
        return 0;
    strcpy(destination, "this string is longer than sixteen bytes");
    return destination[0] == 't' ? 0 : 1;
}
