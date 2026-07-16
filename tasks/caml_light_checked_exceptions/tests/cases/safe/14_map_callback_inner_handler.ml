exception Bad_element;;
let transform x =
  try if x < 0 then raise Bad_element else x
  with Bad_element -> 0;;
list__map transform [1; -2; 3];;

