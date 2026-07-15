/* All eight bytes in p's allocation are nonzero, so no C string terminator
   exists within its bounds. strlen must keep searching for a '\0' and thus
   read out of bounds before it could return. This makes the test interesting
   for library checking: terminator-search routines perform a data-dependent
   number of reads, and the checker must constrain that search to the actual
   allocation rather than trusting the library call or nearby memory. */
#include <stdlib.h>
#include <string.h>

int main(void)
{
    char *p = malloc(8);
    volatile size_t length;
    memset(p, 'x', 8);
    length = strlen(p);
    (void)length;
    return 0;
}
