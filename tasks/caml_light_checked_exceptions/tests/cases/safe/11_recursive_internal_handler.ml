exception Skip;;
let rec sum values =
  match values with
    [] -> 0
  | x :: rest ->
      (try if x < 0 then raise Skip else x with Skip -> 0) + sum rest;;
sum [1; -2; 3];;

