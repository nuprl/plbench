fun mk<S, C>(t :: Table<S>, c :: NewColumn<S, C>):
  t.add-column(c, [list: 7])
end
animals = table: name :: String row: "Sasha" end
res = mk(animals, "z")
print("OBS=" + to-repr(res.column-names()))
