int main(void) {
    int values[16];
    for (int i = 0; i < 16; ++i)
        values[i] = i * i;
    for (int i = 0; i < 16; ++i)
        if (values[i] != i * i)
            return 1;
    return 0;
}
