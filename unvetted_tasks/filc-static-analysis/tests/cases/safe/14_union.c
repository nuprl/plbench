union Number {
    int integer;
    unsigned char bytes[sizeof(int)];
};

int main(void) {
    union Number number;
    number.integer = 0;
    for (unsigned long i = 0; i < sizeof(number.bytes); ++i)
        number.bytes[i] = 0;
    return number.integer;
}
