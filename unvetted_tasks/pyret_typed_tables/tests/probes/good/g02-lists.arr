provide *
import lists as L
nums :: List<Number> = [list: 1, 2, 3]
total :: Number = L.foldl(lam(a :: Number, b :: Number): a + b end, 0, nums)
