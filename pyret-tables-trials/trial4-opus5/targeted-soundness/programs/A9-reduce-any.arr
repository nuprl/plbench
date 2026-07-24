import tables as T
t = table: a :: Number row: 1 row: 2 end
r = t.reduce("a", T.running-sum)
n :: Number = r
print("OBS=" + to-repr(n))
