int main(int argc, char **argv) {
    int values[2] = { 0, 1 };
    if (argc == 37) {
        volatile int result = values[argc];
        (void)result;
    }
    return argv != 0 ? 0 : 1;
}
