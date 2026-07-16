# Checked Exceptions for Caml Light

The task is to add checked exceptions, including type inference for effects, to
the last release of Caml Light from 2002. The verifier has two sets of tests.
The first set has several programs that throw exceptions when run. If the
modified compiler accepts any of them, the overall score is 0. The second set
of programs do not throw an exception, and the score is the fraction of these
programs that the modified compiler accepts. These tests have limitations,
e.g., we are not testing program behavior, so an agent could in principle break
code generation. 
