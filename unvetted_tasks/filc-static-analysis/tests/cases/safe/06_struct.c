struct Pair {
    long left;
    long right;
};

int main(void) {
    struct Pair pair = { 10, 32 };
    struct Pair *p = &pair;
    return p->left + p->right == 42 ? 0 : 1;
}
