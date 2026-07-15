/*
 * Safe: each typed pointer receives a correctly sized allocation, and every
 * store and load stays within that live object. Distinct: this exercises heap
 * accesses through float, double, and long double, including their differing
 * sizes/alignment and conversions to int.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    float *f = malloc(sizeof(*f));
    double *d = malloc(sizeof(*d));
    long double *l = malloc(sizeof(*l));
    *f = 10.5f;
    *d = 20.25;
    *l = 11.25L;
    int total = (int)*f + (int)*d + (int)*l;
    printf("floating-access: total=%d\n", total);
    return 0;
}
