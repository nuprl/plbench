exception During_selection;;
exception During_call;;
let selected =
  try raise During_selection
  with During_selection -> (fun _ -> raise During_call);;
try selected 0 with During_call -> 1;;

