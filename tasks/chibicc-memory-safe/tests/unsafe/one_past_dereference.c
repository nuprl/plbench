/* Forming end as p + 8 is valid: C permits a pointer exactly one element past
   the allocated eight-byte region so it can serve as an iteration boundary.
   Dereferencing end is unsafe, however, because that pointer does not designate
   any byte within the allocation.  This exact boundary is interesting because
   a memory-safe implementation must preserve legal one-past pointer arithmetic
   while rejecting the first out-of-bounds access, rather than rejecting the
   pointer value itself or accidentally allowing the dereference. */
#include <stdlib.h>

int main(void)
{
    char *p = malloc(8);
    char *end = p + 8;
    volatile char value = *end;
    (void)value;
    return 0;
}
