int main(void) {
    volatile int values[8] = { 0 };
    for (int i = 0; i <= 8; ++i)
        values[i] = i;
    return 0;
}
