/*
 * All accesses are safe: every VLA element is initialized, values[0] is in
 * bounds, and end - 1 points to the initialized last element.  This is
 * interesting because end is the permitted one-past pointer for a
 * runtime-sized VLA, and a negative offset moves it back into the array.
 */
#include <stdio.h>

int main(void) {
    int count = 7;
    int values[count];
    for (int i = 0; i < count; i++)
        values[i] = i * i;
    int *end = values + count;
    int *last = end - 1;
    printf("vla: count=%d first=%d last=%d distance=%ld\n",
           count, values[0], *last, (long)(last - values));
    return *last == 36 ? 0 : 1;
}
