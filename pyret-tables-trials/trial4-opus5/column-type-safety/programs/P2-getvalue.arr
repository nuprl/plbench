fun rv<S>(r :: Row<S>, c :: Column<S, Number>) -> Number:
  r.get-value(c)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = rv(animals.row-n(0), "name")
print("OBS=" + num-to-string(bad + 0))
