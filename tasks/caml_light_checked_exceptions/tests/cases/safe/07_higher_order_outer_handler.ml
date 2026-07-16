exception Callback;;
let apply f x = f x;;
try apply (fun _ -> raise Callback) 5 with Callback -> 6;;

