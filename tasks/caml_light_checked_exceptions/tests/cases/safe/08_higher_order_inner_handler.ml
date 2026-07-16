exception Callback;;
let safe_apply f x fallback =
  try f x with Callback -> fallback;;
safe_apply (fun _ -> raise Callback) 1 12;;

