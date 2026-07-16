exception Public_error of int;;

let checked x =
  try
    if x < 0 then raise (Public_error x) else x
  with Public_error n -> 0 - n;;

checked (-4);;

