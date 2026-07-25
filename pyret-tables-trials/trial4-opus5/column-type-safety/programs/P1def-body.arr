fun rd<S>(t :: Table<S>, c :: Column<S, Number>) -> List<Number>:
  t.get-column(c)
end
ok :: Boolean = true
print("DEFINED")
