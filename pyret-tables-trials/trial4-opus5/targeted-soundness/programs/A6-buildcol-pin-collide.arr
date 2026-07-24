fun bc<S>(t :: Table<S>) -> List<Number>:
  t2 = t.build-column("dup", lam(r :: Row<S>) -> Number: 1 end)
  t2.get-column("dup")
end
res = bc(table: dup :: String row: "hi" row: "bye" end)
print("OBS=" + to-repr(res))
