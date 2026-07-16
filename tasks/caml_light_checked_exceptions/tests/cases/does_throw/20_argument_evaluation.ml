exception Argument;;
let ignore_value _ = 0;;
ignore_value (raise Argument);;

