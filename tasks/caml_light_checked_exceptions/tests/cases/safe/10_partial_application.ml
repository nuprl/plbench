exception Final_argument;;
let checked x y = if y = 0 then raise Final_argument else x / y;;
let waiting_for_second_argument = checked 10;;
42;;

