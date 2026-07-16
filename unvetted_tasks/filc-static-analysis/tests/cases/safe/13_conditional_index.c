static int sum_prefix(const int *p, int length) {
    int sum = 0;
    for (int i = 0; i < length; ++i)
        sum += p[i];
    return sum;
}

int main(void) {
    int values[5] = { 1, 2, 3, 4, 5 };
    int length = sizeof(values) / sizeof(values[0]);
    return sum_prefix(values, length) == 15 ? 0 : 1;
}
