/*
 * Safe: both pointers refer to live static objects, and every access remains
 * within its object's bounds.  This is interesting because static pointer
 * relocations must also preserve an interior global pointer such as values + 1.
 */
#include <stdio.h>

static int values[] = {11, 13, 17};
static int *middle = values + 1;
static int scalar = 19;
static int *scalar_pointer = &scalar;

int main(void) {
    printf("global-pointer: before=%d current=%d after=%d scalar=%d\n",
           middle[-1], middle[0], middle[1], *scalar_pointer);
    return 0;
}
