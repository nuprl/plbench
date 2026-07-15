/* This write is unsafe even though pair.right is laid out immediately after
   pair.left: left[4] crosses the left array's boundary and accesses a distinct
   sibling subobject, rather than remaining within the object designated by the
   pointer. Static initialization of this interior pointer must therefore retain
   pair.left's subobject bounds; treating it as bounded by the enclosing pair
   would incorrectly permit the out-of-bounds access into pair.right. */
struct pair {
    char left[4];
    char right[4];
};

static struct pair pair;
static char *left = pair.left;

int main(void) {
    left[4] = 42;
    return 0;
}
