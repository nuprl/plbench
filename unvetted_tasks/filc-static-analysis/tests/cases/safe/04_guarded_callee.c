static int read_at(const int *values, int length, int index) {
    if (index < 0 || index >= length)
        return -1;
    return values[index];
}

int main(void) {
    int values[] = { 3, 5, 8, 13 };
    return read_at(values, 4, 2) == 8 ? 0 : 1;
}
