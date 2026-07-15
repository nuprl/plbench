/* Automatic-object lifetime: a is allocated only for the invocation of
   escape, so returning from escape ends a's lifetime even though its address
   has escaped to main. The returned pointer is therefore stale, and reading
   through it must fail. This case is interesting because temporal checking
   must preserve and recognize invalidation across a function-return boundary,
   rather than merely detecting an out-of-bounds access within one frame. */
static char *escape(void)
{
    char a[8];
    a[0] = 42;
    return a;
}

int main(void)
{
    char *p = escape();
    volatile char value = *p;
    (void)value;
    return 0;
}
