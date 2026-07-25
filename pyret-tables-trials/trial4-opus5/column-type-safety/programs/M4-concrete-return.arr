fun mk(t :: Table<{name :: String}>) -> Table<{name :: String, z :: Number}>:
  t.add-column("z", [list: 7])
end
animals = table: name :: String row: "Sasha" end
print("OBS=" + to-repr(mk(animals).column-names()))
