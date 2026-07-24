fun needs-num(tt :: Table<{a :: Number}>) -> List<Number>:
  tt.get-column("a")
end
t2 = (table: a :: Number row: 5 end).transform-column("a", lam(x): num-to-string(x) end)
print("OBS=" + to-repr(needs-num(t2)))
