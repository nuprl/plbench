fun g<S>(t :: Table<S>) -> Table<S, {c :: Number}>:
  t.add-column("c", [list: 99])
end
res = g(table: c :: String row: "old" end)
ys :: List<Number> = res.get-column("c")
print("OBS=" + to-repr(ys))
