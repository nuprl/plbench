exception Original;;
let middle () =
  try raise Original with exn -> raise exn;;
try middle () with Original -> ();;

