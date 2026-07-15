/* Both buffers hold exactly six bytes: memcpy includes the source terminator,
 * strlen stays within it, strcpy copies all six bytes, and every indexed access
 * is in range. This exercises interoperability among checked memcpy, strlen,
 * and strcpy while preserving valid object bounds and C-string termination. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    char *src = malloc(6);
    char *dst = malloc(6);
    memcpy(src, "hello", 6);
    if (strlen(src) != 5)
        return 1;
    strcpy(dst, src);
    int ok = dst[4] == 'o' && dst[5] == '\0';
    printf("strings: text=%c%c%c%c%c length=%d last=%c\n",
           dst[0], dst[1], dst[2], dst[3], dst[4],
           (int)strlen(dst), dst[4]);
    free(src);
    free(dst);
    return ok ? 0 : 1;
}
