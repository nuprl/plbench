fun anylist() -> List<Any>: [list: "str"] end
t = table: a :: Number row: 1 end
t2 :: Table<{a :: Number, b :: Number}> = t.add-column("b", anylist())
zs :: List<Number> = t2.get-column("b")
print("OBS=" + to-repr(zs))
