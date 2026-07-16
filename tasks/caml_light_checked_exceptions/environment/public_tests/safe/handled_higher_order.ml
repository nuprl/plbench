exception Callback_failed;;

let apply f x = f x;;

let result =
  try apply (fun _ -> raise Callback_failed) 3
  with Callback_failed -> 7;;

result;;

