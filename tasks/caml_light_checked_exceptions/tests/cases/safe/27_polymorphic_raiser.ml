exception Polymorphic;;
let abort _ = raise Polymorphic;;
let as_int = try abort 1 with Polymorphic -> 10;;
let as_string = try abort "x" with Polymorphic -> "ok";;
(as_int, as_string);;

