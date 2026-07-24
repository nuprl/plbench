fun renb(t :: Table<{a :: Number}>) -> Table<{b :: Number}>:
  t.rename-column("a", "b")
end
res = renb(table: a :: Number, b :: String row: 1, "str-b" end)
print("OBS=" + to-repr(res.get-column("b")))
