/*
 * This program is safe: every dereference is of a successfully allocated
 * object that remains reachable through a global or stack root. It is an
 * interesting collector test because it combines a reachable cycle, many
 * unreachable cycles, both kinds of roots, and forced collections that must
 * reclaim garbage without disturbing live objects.
 */
#include <stdio.h>
#include <stdlib.h>

void __safe_collect(void);

struct Node {
    struct Node *next;
    int value;
    unsigned char payload[64 * 1024];
};

static struct {
    int collection_epoch;
    struct Node *cycle;
    struct Node *other_roots[2];
} global_roots;

int main(void) {
    struct Node *stack_root = malloc(sizeof(*stack_root));
    if (!stack_root)
        return 2;
    stack_root->next = NULL;
    stack_root->value = 314;

    struct Node *first = malloc(sizeof(*first));
    struct Node *second = malloc(sizeof(*second));
    if (!first || !second)
        return 2;
    first->next = second;
    first->value = 42;
    second->next = first;
    second->value = 99;
    global_roots.collection_epoch = 7;
    global_roots.cycle = first;
    first = NULL;
    second = NULL;

    // Force a collection with a shallow heap. The cycle is reachable only
    // through the pointer stored in static data; stack_root is independently
    // protected only by an automatic pointer variable.
    __safe_collect();
    if (stack_root->value != 314)
        return 5;

    enum { cycles = 16384 };
    unsigned long checksum = 0;
    for (int i = 0; i < cycles; i++) {
        struct Node *left = malloc(sizeof(*left));
        struct Node *right = malloc(sizeof(*right));
        if (!left || !right)
            return 3;

        left->next = right;
        right->next = left;
        left->payload[0] = (unsigned char)i;
        right->payload[0] = (unsigned char)(i * 7);
        checksum += left->payload[0];
        checksum += right->payload[0];

        // Drop the only roots to this cycle. Reference counting cannot
        // reclaim it, but tracing collection can.
        left = NULL;
        right = NULL;
        if ((i & 15) == 15)
            __safe_collect();
    }

    __safe_collect();
    int saved = global_roots.cycle->value + global_roots.cycle->next->value;
    saved += global_roots.collection_epoch - 7;
    printf("gc-cycles: cycles=%d checksum=%lu saved=%d stack=%d\n",
           cycles, checksum, saved, stack_root->value);
    return saved == 141 && stack_root->value == 314 ? 0 : 4;
}
