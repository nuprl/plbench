fun conv<S, C>(t :: Table<S>, nc :: NewColumn<S, C>) -> List<Number>:
  c :: Column<S, C, Number> = nc
  t.get-column(c)
end
animals = table: name :: String, age :: Number row: "Sasha", 3 end
bad = conv(animals, "brand-new")
print("OBS=" + to-repr(bad))
