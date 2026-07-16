exception Final_argument;;
let divide_checked x y =
  if y = 0 then raise Final_argument else x / y;;
divide_checked 10 0;;

