/* Checked string copying must account for the destination, not just for reads
   from the source.  src holds eight visible characters followed by the NUL
   terminator that strcpy also copies, so the destination write is nine bytes
   even though strlen(src) is eight.  This makes destination sizing especially
   interesting for checked string-copy operations: an eight-byte dst fits the
   characters but not the required terminator and must therefore be rejected. */
#include <stdlib.h>
#include <string.h>

int main(void)
{
    char *src = malloc(9);
    char *dst = malloc(8);
    memcpy(src, "12345678", 9);
    strcpy(dst, src);
    return 0;
}
