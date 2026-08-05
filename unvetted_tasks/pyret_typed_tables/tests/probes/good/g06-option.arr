provide *
import option as O
fun first-or-zero(l :: List<Number>) -> Number:
  cases(List) l:
    | empty => 0
    | link(f, _) => f
  end
end
