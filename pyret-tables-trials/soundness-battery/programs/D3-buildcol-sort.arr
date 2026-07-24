fun needs-num(tt :: Table<{a :: Number, b :: Number}>) -> List<Number>:
  tt.get-column("b")
end
t2 = (table: a :: Number row: 1 end).build-column("b", lam(r): "not-num" end)
print("OBS=" + to-repr(needs-num(t2)))
