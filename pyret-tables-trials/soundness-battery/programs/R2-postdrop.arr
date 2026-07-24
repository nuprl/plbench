t = table: name :: String, age :: Number
  row: "A", 1
end
x = t.drop("age").get-column("age")
