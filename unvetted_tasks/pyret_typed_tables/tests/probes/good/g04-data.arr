provide *
data Shape:
  | circle(radius :: Number)
  | rect(w :: Number, h :: Number)
end
fun area(s :: Shape) -> Number:
  cases(Shape) s:
    | circle(r) => 3 * r * r
    | rect(w, h) => w * h
  end
end
