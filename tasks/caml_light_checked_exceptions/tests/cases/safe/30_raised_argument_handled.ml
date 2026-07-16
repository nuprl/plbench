exception Argument;;
let ignore_value _ = 0;;
try ignore_value (raise Argument) with Argument -> 1;;

