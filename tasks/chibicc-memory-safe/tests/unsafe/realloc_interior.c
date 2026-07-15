/* realloc requires the allocation's base pointer because it resizes the whole
   allocated object, whose bounds and lifetime are associated with that base;
   an interior pointer does not identify an allocation that may be resized.
   This case is interesting because realloc is non-destructive here: validation
   must still reject the interior pointer even though the original allocation
   remains valid and no invalidation side effect can reveal the bad argument. */
#include <stdlib.h>

int main(void) {
    char *p = malloc(8);
    (void)realloc(p + 1, 16);
    return 0;
}
