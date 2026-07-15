/* Safe: begin and the one-past end pointer belong to the same global array;
 * recursion stops before dereferencing end. This exercises legal one-past
 * traversal, same-array pointer difference/comparison, global storage, and
 * recursive propagation of bounded pointers.
 */
#include <stddef.h>
#include <stdio.h>

static int values[] = {3, 5, 8, 13, 21};

static int sum(const int *cursor, const int *end) {
    if (cursor == end)
        return 0;
    return *cursor + sum(cursor + 1, end);
}

int main(void) {
    int *begin = values;
    int *end = values + 5;
    ptrdiff_t count = end - begin;
    int total = sum(begin, end);
    printf("global-recursion: count=%ld total=%d ordered=%d\n",
           (long)count, total, begin < end);
    return count == 5 && total == 50 ? 0 : 1;
}
