# MiniScheme proper-tail-call compiler

This task asks for a MiniScheme-to-MiniScheme compiler that makes calls safe
under the reference interpreter's optional logical stack-depth limit.

The Oracle performs a whole-program CPS conversion. Each transformed step
stores a zero-argument thunk in a mutable `next` variable. A `while` loop calls
one thunk per iteration until the halt continuation clears a mutable `running`
flag. The evaluator has no special trampoline protocol.

The verifier obtains expected behavior by running each hidden source program
on the unlimited interpreter, then runs compiled output with
`--max-stack-depth 50` and compares process outcome and stdout.
