fun mk<S, C>(t :: Table<S>, c :: NewColumn<S, C>) -> Table<S, {C; Number}>:
  t.add-column(c, [list: "str"])
end
animals = table: name :: String row: "Sasha" end
res = mk(animals, "newc")
xs :: List<Number> = res.get-column("newc")
print("OBS=" + to-repr(xs))
