fun s() -> Any: "surprise" end
t = table: n :: Number row: s() end
xs :: List<Number> = t.get-column("n")
print("OBS=" + to-repr(xs))
