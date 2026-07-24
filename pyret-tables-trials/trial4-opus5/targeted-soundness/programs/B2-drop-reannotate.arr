fun f<S>(t :: Table<S, {b :: Number}>) -> Table<S>:
  t.drop("b")
end
g = f(table: a :: String, b :: Number row: "hi", 1 end)
bad :: Table<{a :: Number}> = g
xs :: List<Number> = bad.get-column("a")
print("OBS=" + to-repr(xs))
