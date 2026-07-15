/* malloc(16) makes p point at the first byte of a 16-byte heap object, so
   p[-1] attempts to store one byte before that object's lower bound and is
   therefore unsafe. Negative offsets are interesting because checking only
   the upper bound (or treating an index as unsigned incorrectly) can miss
   left-side out-of-bounds accesses; this store must produce a checked failure. */
#include <stdlib.h>

int main(void)
{
    char *p = malloc(16);
    p[-1] = 1;
    return 0;
}
