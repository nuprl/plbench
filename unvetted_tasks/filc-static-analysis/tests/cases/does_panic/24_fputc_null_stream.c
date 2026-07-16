#include <stdio.h>

int main(void) {
    return fputc('x', (FILE *)0);
}
