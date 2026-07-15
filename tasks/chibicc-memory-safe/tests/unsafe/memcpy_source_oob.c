/* The destination has enough space for all eight bytes, but the source
   allocation contains only seven readable bytes, so reading the eighth byte
   makes this memcpy unsafe. This case is interesting because it requires the
   source and destination ranges to be validated independently: a valid
   destination must not conceal an out-of-bounds source read. */
#include <stdlib.h>
#include <string.h>

int main(void)
{
    char *src = malloc(7);
    char *dst = malloc(8);
    memcpy(dst, src, 8);
    return 0;
}
