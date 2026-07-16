#include <string.h>

int main(void) {
    char source[6] = "hello";
    char destination[6];
    memcpy(destination, source, sizeof(source));
    return strcmp(destination, "hello") == 0 ? 0 : 1;
}
