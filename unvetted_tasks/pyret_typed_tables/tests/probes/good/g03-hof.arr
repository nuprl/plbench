provide *
fun apply-twice<A>(f :: (A -> A), x :: A) -> A:
  f(f(x))
end
result :: Number = apply-twice(lam(n :: Number): n + 1 end, 0)
