/*
 * This program is memory-safe: every allocation is checked before use, the
 * byte-block accesses stay at the first and last valid indices, and every
 * Node is fully initialized before the rooted list is traversed.  Omitting
 * free is intentional because the test exercises automatic garbage
 * collection rather than manual deallocation.
 *
 * The loop allocates 2 GiB cumulatively while retaining at most its current
 * block, stressing reclamation and address-space reuse without requiring a
 * large live heap.  In contrast, global_root keeps a linked graph reachable
 * across that pressure; its final sum checks that tracing preserves genuinely
 * live objects while reclaiming the short-lived blocks.
 */
#include <stdio.h>
#include <stdlib.h>

struct Node {
    struct Node *next;
    int value;
};

static struct Node *global_root;

int main(void) {
    enum { iterations = 8192, block_size = 256 * 1024 };
    unsigned long checksum = 0;

    for (int i = 1; i <= 64; i++) {
        struct Node *node = malloc(sizeof(*node));
        if (!node)
            return 3;
        node->next = global_root;
        node->value = i;
        global_root = node;
    }

    for (int i = 0; i < iterations; i++) {
        unsigned char *block = malloc(block_size);
        if (!block) {
            printf("gc: allocation failed at iteration %d\n", i);
            return 2;
        }

        block[0] = (unsigned char)i;
        block[block_size - 1] = (unsigned char)(i * 3);
        checksum += block[0];
        checksum += block[block_size - 1];

        // `block` is overwritten on the next iteration. Therefore all but
        // the current allocation become unreachable without an explicit free.
    }

    int retained_sum = 0;
    for (struct Node *node = global_root; node; node = node->next)
        retained_sum += node->value;

    printf("gc: allocated-mib=%lu checksum=%lu retained-sum=%d\n",
           iterations * (unsigned long)block_size / (1024 * 1024),
           checksum, retained_sum);
    return retained_sum == 2080 ? 0 : 4;
}
