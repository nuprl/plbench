/* This store is unsafe because the runtime-sized VLA contains argc + 4
   elements, so bytes[argc + 4] designates the one-past pointer and is not a
   valid object to write. Dynamic VLA bounds are interesting because the exact
   allocation size and failing address depend on a runtime value, so spatial
   safety checks cannot rely only on compile-time constant array extents. */
int main(int argc, char **argv)
{
    volatile char bytes[argc + 4];
    (void)argv;
    bytes[argc + 4] = 1;
    return 0;
}
