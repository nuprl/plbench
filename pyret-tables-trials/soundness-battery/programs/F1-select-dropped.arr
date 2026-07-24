t = table: a :: Number, b :: String, c :: Number
  row: 1, "x", 2
end
sel = select a, c from t end
print("OBS=" + to-repr(sel.get-column("b")))
