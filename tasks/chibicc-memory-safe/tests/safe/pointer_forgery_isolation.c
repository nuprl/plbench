/*
 * Safe: the forged pointer is never used to access memory. Creating it must
 * not invalidate the separate valid alias, which remains usable afterward.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    int *valid = malloc(sizeof(*valid));
    *valid = 41;

    uintptr_t bits = (uintptr_t)valid;
    int *forged = (int *)bits;
    (void)forged;

    ++*valid;
    printf("forgery-isolation: valid=%d\n", *valid);
    return 0;
}
