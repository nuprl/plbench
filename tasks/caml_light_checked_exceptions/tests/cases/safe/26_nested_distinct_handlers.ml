exception Inner;;
exception Outer;;
let work b =
  try
    if b then raise Inner else raise Outer
  with Inner -> 1;;
try work false with Outer -> 2;;

