static int read_at(const int *values, int index) {
    return values[index];
}

int main(void) {
    int values[2] = { 10, 20 };
    volatile int result = read_at(values, 7);
    (void)result;
    return 0;
}
