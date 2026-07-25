fun rd3<S, C>(t :: Table<S>, c :: Column<S, C, Number>) -> List<Number>:
  t.get-column(c)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = rd3(animals, "name")
print("OBS=" + to-repr(bad))
