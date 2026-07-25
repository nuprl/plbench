type NumCol = Column<{name :: String, age :: Number}, Number>
fun rd(t :: Table<{name :: String, age :: Number}>, c :: NumCol) -> List<Number>:
  t.get-column(c)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = rd(animals, "name")
print("OBS=" + to-repr(bad))
