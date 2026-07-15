/* Dereferencing a null pointer is unsafe because it does not point to a valid
   object, so the attempted read has no legitimate memory location to access.
   Deterministic checked null handling is interesting because it reports this
   specific error predictably instead of relying on a raw, platform-dependent
   signal. */
int main(void)
{
    volatile int value = *(int *)0;
    (void)value;
    return 0;
}
