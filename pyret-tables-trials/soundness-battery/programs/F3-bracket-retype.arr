fun needs-num(n :: Number) -> Number: n end
t2 = (table: a :: Number row: 5 end).transform-column("a", lam(x): num-to-string(x) end)
print("OBS=" + to-repr(needs-num(t2.row-n(0)["a"])))
