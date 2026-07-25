fun mk<S, C>(t :: Table<S>, c :: NewColumn<S, C>) -> Table<S, {C; Number}>:
  t.add-column("other", [list: 1])
end
animals = table: name :: String row: "Sasha" end
res = mk(animals, "newc")
print("OBS=" + to-repr(res.column-names()))
