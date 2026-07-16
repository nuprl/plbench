exception Selected;;
let choose b =
  if b then (fun _ -> raise Selected) else (fun x -> x);;
(choose true) 4;;

