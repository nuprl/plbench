opaque :: Any = table: age :: String row: "x" row: "y" end
retyped :: Table<{age :: Number}> = opaque
nums :: List<Number> = retyped.get-column("age")
print("OBS=" + to-repr(nums))
