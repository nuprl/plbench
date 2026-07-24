fun f<S>(t :: Table<S, {b :: Number}>) -> Table<S>:
  t.drop("b")
end
mk = table: x :: String, b :: Number row: "hi", 7 end
res = f(mk)
xs :: List<String> = res.get-column("x")
print("OBS=" + to-repr(xs))
