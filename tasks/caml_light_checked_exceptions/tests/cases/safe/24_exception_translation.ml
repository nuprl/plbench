exception Low_level;;
exception High_level;;
let translated () =
  try raise Low_level with Low_level -> raise High_level;;
try translated () with High_level -> 0;;

