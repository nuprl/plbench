t1 = table: a :: Number row: 1 end
t2 = table: a :: Number, x :: String row: 2, "s" end
print("OBS=" + to-repr(t1.stack(t2)))
