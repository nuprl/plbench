fun rn<S>(t :: Table<S, {old :: Number}>) -> Table:
  t.rename-column("old", "new")
end
res = rn(table: k :: String, old :: Number row: "a", 5 end)
print("OBS-type=" + to-repr(res.column-names()))
