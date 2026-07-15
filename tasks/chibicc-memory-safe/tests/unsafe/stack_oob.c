/* Spatial safety for automatic arrays: valid indices for this eight-byte array
   are 0 through 7, so storing through a[8] writes one past the array and is
   unsafe even if the address still lies in mapped stack memory. Stack-object
   bounds are especially interesting because adjacent locals, saved state, or
   other live frame data may occupy that memory, so checking only whether an
   address belongs to the stack cannot protect the individual object. */
int main(void)
{
    volatile char a[8];
    a[8] = 42;
    return 0;
}
