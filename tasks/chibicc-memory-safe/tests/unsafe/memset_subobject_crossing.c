/* This memset starts from pair.left, so its writable object is the left array
   subobject, not the whole enclosing Pair. Crossing the boundary into right is
   therefore unsafe even though both arrays occupy contiguous storage inside
   the same live struct. This case is interesting because a bulk-operation
   check must validate the entire byte range against the originating subobject;
   checking only that the start address and allocation are valid would miss the
   subobject-boundary violation. */
#include <string.h>

struct Pair {
    char left[4];
    char right[4];
};

int main(void) {
    struct Pair pair = {{0}, {0}};
    memset(pair.left, 1, sizeof(pair));
    return 0;
}
