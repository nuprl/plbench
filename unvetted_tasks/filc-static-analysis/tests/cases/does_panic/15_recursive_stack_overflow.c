static volatile int stop;

static int descend(unsigned depth) {
    if (stop)
        return (int)depth;
    return descend(depth + 1) + stop;
}

int main(void) {
    return descend(0);
}
