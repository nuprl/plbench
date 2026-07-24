t = table: a :: Number, b :: String
  row: 1, "x"
end
s = select b from t.drop("b") end
print("OBS=" + to-repr(s))
