/* This program is unsafe because p points to storage for exactly one double,
   so reading p[1] performs an out-of-bounds load starting just past the object.
   Full-width floating-point load coverage is interesting because the checker
   must validate every byte of the multi-byte double access, not merely its
   starting address or only integer loads. */
#include <stdlib.h>

int main(void) {
    double *p = malloc(sizeof(*p));
    volatile double value = p[1];
    (void)value;
    return 0;
}
