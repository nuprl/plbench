exception Callback_escapes;;

let apply f x = f x;;

apply (fun _ -> raise Callback_escapes) 0;;

