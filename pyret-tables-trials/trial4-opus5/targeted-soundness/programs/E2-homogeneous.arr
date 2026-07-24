fun h<S>(t :: Table<S, {n :: Number}>) -> List<Number>:
  t.column-n(0)
end
res = h(table: s :: String, n :: Number row: \"z\", 3 end)
print(\"OBS=\" + to-repr(res))
