fun launder<S, C>(t :: Table<S>, c :: Column<S, C, String>) -> List<Number>:
  s :: String = c
  c2 :: Column<S, Number> = s
  t.get-column(c2)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = launder(animals, "name")
print("OBS=" + to-repr(bad))
