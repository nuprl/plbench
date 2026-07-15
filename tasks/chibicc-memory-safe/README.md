# Memory Safety for Chibicc

This task is to add memory safety to the Chibicc Compiler, for the C99 subset of
the language. The instructions explicitly ask for temporary and spatial memory
safety, garbage collection, and a few other details. The oracle was built GPT
5.6 Sol Medium with reference to the Fil-C source code. The instructions state
that a memory access that is even one byte outside the bounds of an object or
subobject is a memory-safety violation. This requirement makes it hard to write
a high-performance implementation such as Fil-C, but it is the task at hand.