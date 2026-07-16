exception At_zero;;
let rec descend n =
  if n = 0 then raise At_zero else descend (n - 1);;
descend 5;;

