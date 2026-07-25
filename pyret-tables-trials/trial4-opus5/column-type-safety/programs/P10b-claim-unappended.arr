fun mk<S, C>(t :: Table<S>, c :: NewColumn<S, C>) -> Table<S, {C; Number}>:
  t.add-column(c, [list: 7])
end
animals = table: name :: String row: "Sasha" end
res = mk(animals, "z")
# read the ORIGINAL name column, claimed via a fresh mis-annotation route
zs :: List<Number> = res.get-column("z")
print("OBS=" + to-repr(zs))
