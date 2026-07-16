exception Stored;;
let functions = [(fun x -> x + 1); (fun _ -> raise Stored)];;
try
  let selected = list__hd (list__tl functions) in
  selected 3
with Stored -> 4 | Failure _ -> 4;;
