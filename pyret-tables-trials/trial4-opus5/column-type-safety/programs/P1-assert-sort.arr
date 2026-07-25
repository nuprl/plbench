fun rd<S>(t :: Table<S>, c :: Column<S, Number>) -> List<Number>:
  t.get-column(c)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = rd(animals, "name")
n :: Number = bad.get(0)
print("OBS=" + num-to-string(n + 0))
