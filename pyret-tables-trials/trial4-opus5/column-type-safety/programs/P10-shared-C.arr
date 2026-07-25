fun mk<S, C>(t :: Table<S>, c :: NewColumn<S, C>, d :: NewColumn<S, C>) -> Table<S, {C; Number}>:
  t.add-column(d, [list: 1])
end
animals = table: name :: String row: "Sasha" end
res = mk(animals, "x", "y")
xs :: List<Number> = res.get-column("x")
print("OBS=" + to-repr(xs))
