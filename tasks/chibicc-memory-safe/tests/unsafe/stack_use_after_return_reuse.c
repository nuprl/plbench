/* The pointer returned by escape becomes stale when value's lifetime ends.
   It remains unsafe to dereference even if consume's replacement happens to
   reuse exactly the same numeric stack address: replacement is a new object
   with a distinct lifetime, not a continuation of value. This makes the test
   interesting for lifetime-identity tracking, which rejects the stale pointer,
   versus address-only checks, which may incorrectly accept it as in bounds. */
static int *escape(void) {
    int value = 42;
    return &value;
}

static int consume(int *stale) {
    int replacement = 7;
    volatile int value = *stale;
    return value + replacement;
}

int main(void) {
    return consume(escape());
}
