/*
 * This program is safe: it accesses each allocated block only while its pointer
 * is live, then drops that pointer before collection.  The saved uintptr_t bit
 * patterns are integers, not pointers, so they must not keep the blocks alive
 * as garbage-collector roots.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void __safe_collect(void);

static uintptr_t old_addresses[32];

int main(void) {
    enum { count = 32, block_size = 32 * 1024 * 1024 };
    unsigned long checksum = 0;

    for (int i = 0; i < count; i++) {
        unsigned char *block = malloc(block_size);
        if (!block)
            return 2;
        block[0] = (unsigned char)(i + 1);
        checksum += block[0];
        old_addresses[i] = (uintptr_t)block;
        block = NULL;
        __safe_collect();
    }

    printf("gc-integers: allocated-mib=%d checksum=%lu\n",
           count * block_size / (1024 * 1024), checksum);
    return 0;
}
