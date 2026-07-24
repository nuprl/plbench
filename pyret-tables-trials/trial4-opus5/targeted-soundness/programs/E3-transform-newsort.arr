t = table: a :: Number row: 1 row: 2 end
t2 = transform t using a: a: to-repr(a) end
xs :: List<String> = t2.get-column("a")
print("OBS=" + to-repr(xs))
