#include <string.h>

int main(void) {
    char destination[1] = {0};
    char source[1] = {0};

    memcpy(destination, source, (size_t)-1);
    return 0;
}
