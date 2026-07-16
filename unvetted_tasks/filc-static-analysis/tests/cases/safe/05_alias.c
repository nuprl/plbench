static void set_first(int *p) {
    *p = 17;
}

int main(void) {
    int value = 0;
    int *alias = &value;
    set_first(alias);
    return value == 17 ? 0 : 1;
}
