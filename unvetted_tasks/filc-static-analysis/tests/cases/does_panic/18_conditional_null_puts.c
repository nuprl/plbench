#include <stdio.h>

int main(int argc, char **argv) {
    char *text = "safe";
    (void)argv;
    while (argc-- > 1)
        text = 0;
    return puts(text);
}
