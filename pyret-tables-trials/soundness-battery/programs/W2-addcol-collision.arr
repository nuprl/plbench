fun addb(t :: Table<{a :: Number}>) -> Table<{a :: Number, b :: Number}>:
  t.add-column("b", [list: 100])
end
res = addb(table: a :: Number, b :: String row: 1, "str-b" end)
print("OBS=" + to-repr(res.get-column("b")))
