/* bytes[8] designates the one-past address of this eight-byte global array.
   C permits forming that address for pointer arithmetic, but the address is
   outside the array and storing through it is an unsafe out-of-bounds access.
   This case is interesting because globals have static storage and lifetime,
   yet each global object still has its own bounds; safety therefore cannot
   rely only on mechanisms that cover heap or stack objects. */
static volatile char bytes[8];

int main(void)
{
    bytes[8] = 1;
    return 0;
}
