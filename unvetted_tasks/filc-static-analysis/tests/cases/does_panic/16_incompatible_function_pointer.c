typedef void (*NoArg)(void);

static void takes_pointer(int *p) {
    *p = 1;
}

int main(void) {
    NoArg function = (NoArg)takes_pointer;
    function();
    return 0;
}
