fun s(x) -> Any: "str" end
t = table: a :: Number row: 1 end
t2 = extend t using a: bad :: Number: s(a) end
zs :: List<Number> = t2.get-column("bad")
print("OBS=" + to-repr(zs))
