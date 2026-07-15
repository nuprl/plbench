/* Subobject bounds: left has exactly four elements, indexed 0 through 3, so
   left[4] is one-past the end and cannot be dereferenced. Its numeric address
   may coincide with right[0], but that physical adjacency does not make an
   access through left valid. This case is interesting because checking only
   the enclosing struct's bounds would accept the store, whereas memory safety
   must preserve the bounds of the array subobject from which the access arose. */
struct pair {
    char left[4];
    char right[4];
};

int main(void)
{
    struct pair p = {{0}, {0}};
    p.left[4] = 42;
    return 0;
}
