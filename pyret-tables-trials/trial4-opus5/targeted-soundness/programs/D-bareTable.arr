t :: Table = table: age :: String row: "x" row: "y" end
retyped :: Table<{age :: Number}> = t
nums :: List<Number> = retyped.get-column("age")
print("OBS=" + to-repr(nums))
