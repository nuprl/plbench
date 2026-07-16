exception Bad_element of int;;
let transform x = if x = 3 then raise (Bad_element x) else x + 1;;
try list__map transform [1; 2; 3; 4] with Bad_element n -> [n];;

