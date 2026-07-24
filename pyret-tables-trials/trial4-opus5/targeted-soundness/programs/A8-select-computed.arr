t = table: a :: Number, b :: String row: 1, "x" end
nm = "b"
picked = t.select-columns([list: nm])
xs :: List<Number> = picked.get-column("a")
print("OBS=" + to-repr(xs))
