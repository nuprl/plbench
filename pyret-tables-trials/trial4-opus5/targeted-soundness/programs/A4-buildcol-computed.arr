t = table: a :: Number row: 1 row: 2 end
nm = "b" + "x"
t2 = t.build-column(nm, lam(r :: Row<{a :: Number}>) -> Boolean: r["a"] > 1 end)
# t2 result schema pins nothing (name not literal). Try to read new col as Number:
zs :: List<Number> = t2.column-n(1)
print("OBS=" + to-repr(zs))
