fun idt<S>(t :: Table<S>) -> Table<S>: t end
animals = table: name :: String row: "Sasha" end
print("OBS=" + to-repr(idt(animals).column-names()))
