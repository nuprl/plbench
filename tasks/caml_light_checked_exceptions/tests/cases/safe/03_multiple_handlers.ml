exception Left;;
exception Right;;
let choose b = if b then raise Left else raise Right;;
try choose true with Left -> 1 | Right -> 2;;

