fun needs-num(tt :: Table<{v :: Number}>) -> List<Number>:
  tt.get-column("v")
end
print("OBS=" + to-repr(needs-num(table: v :: String end)))
