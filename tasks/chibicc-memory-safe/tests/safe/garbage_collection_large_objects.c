/*
 * Each allocation is accessed only within its bounds while live, so the program
 * is memory-safe. A few large blocks quickly become unreachable, creating high
 * byte pressure that tests whether automatic collection is triggered by bytes
 * consumed rather than merely by the number of allocations.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    enum { iterations = 64, block_size = 32 * 1024 * 1024 };
    unsigned long checksum = 0;

    for (int i = 0; i < iterations; i++) {
        unsigned char *block = malloc(block_size);
        if (!block)
            return 2;
        block[0] = (unsigned char)i;
        block[block_size - 1] = (unsigned char)(i * 5);
        checksum += block[0] + block[block_size - 1];
    }

    printf("gc-large: allocated-mib=%lu checksum=%lu\n",
           iterations * (unsigned long)block_size / (1024 * 1024), checksum);
    return 0;
}
