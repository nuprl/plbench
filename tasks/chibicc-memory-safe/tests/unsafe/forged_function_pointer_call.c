/*
 * This program is unsafe because the integer value supplies no authority to
 * call a function, yet the converted function pointer is invoked. It is an
 * interesting control-flow counterpart to forged data pointers: an
 * implementation must reject the indirect call with a checked diagnostic
 * rather than transferring control to an arbitrary native address or merely
 * crashing on a hardware fault.
 */
#include <stdint.h>

int main(void) {
    uintptr_t bits = 1;
    void (*function)(void) = (void (*)(void))bits;
    function();
    return 0;
}
