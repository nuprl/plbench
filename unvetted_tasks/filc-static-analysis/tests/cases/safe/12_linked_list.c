#include <stdlib.h>

struct Node {
    int value;
    struct Node *next;
};

int main(void) {
    struct Node *first = malloc(sizeof(struct Node));
    struct Node *second = malloc(sizeof(struct Node));
    if (!first || !second)
        return 0;
    first->value = 20;
    first->next = second;
    second->value = 22;
    second->next = NULL;
    int result = first->value + first->next->value;
    free(second);
    free(first);
    return result == 42 ? 0 : 1;
}
