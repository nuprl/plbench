exception Callback;;
let apply f x = f x;;
apply (fun _ -> raise Callback) 3;;

