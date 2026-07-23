provide *
data Box:
  | box(v :: Number)
end
fun unwrap(b :: Box) -> Number:
  cases(Box) b:
    | box(v) => "not a number"
  end
end
