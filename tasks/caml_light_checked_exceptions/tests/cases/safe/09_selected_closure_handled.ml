exception Selected;;
let choose b =
  if b then (fun _ -> raise Selected) else (fun x -> x);;
try (choose true) 4 with Selected -> 5;;

