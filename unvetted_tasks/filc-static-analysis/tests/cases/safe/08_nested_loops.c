int main(void) {
    int matrix[4][5] = { { 0 } };
    for (int row = 0; row < 4; ++row)
        for (int column = 0; column < 5; ++column)
            matrix[row][column] = row + column;
    return matrix[3][4] == 7 ? 0 : 1;
}
