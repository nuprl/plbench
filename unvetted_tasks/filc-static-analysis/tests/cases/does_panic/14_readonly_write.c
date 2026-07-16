int main(void) {
    char *text = (char *)"immutable";
    text[0] = 'I';
    return text[0];
}
