int main(void) {
    int values[3] = { 1, 2, 3 };
    int *begin = values;
    int *end = values + 3;
    int sum = 0;
    while (begin != end)
        sum += *begin++;
    return sum == 6 ? 0 : 1;
}
