fun usea(t :: Table<{a :: Number}>) -> List<Number>:
  t.get-column("a")
end
print("OBS=" + to-repr(usea(table: a :: String row: "xyz" end)))
