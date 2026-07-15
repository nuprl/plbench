/* This task classifies pointer-consuming printf formats such as %s as unsafe:
   the host library would dereference a pointer without the checks applied to
   ordinary pointer accesses in the compiled program.  This boundary is also
   interesting because printf is both external and variadic, so the pointer's
   meaning is determined only by the format string rather than by a parameter
   type that the compiler can validate directly. */
#include <stdio.h>

int main(void) {
    printf("%s\n", "unsafe boundary");
    return 0;
}
