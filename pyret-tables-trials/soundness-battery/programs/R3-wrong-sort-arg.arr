fun needs-num(t :: Table<{q :: Number}>) -> List<Number>:
  t.get-column("q")
end
y = needs-num(table: q :: String row: "s" end)
