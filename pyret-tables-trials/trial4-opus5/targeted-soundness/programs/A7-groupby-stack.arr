fun keycol<S, C, T>(t :: Table<S>, k :: Column<S, C, T>) -> Table<{C; T}>:
  t.select-columns([list: k])
end
t1 = table: a :: Number, b :: String row: 1, "x" end
p1 = keycol(t1, "a")
p2 = keycol(t1, "b")
merged = p1.stack(p2)
print("OBS=" + to-repr(merged))
