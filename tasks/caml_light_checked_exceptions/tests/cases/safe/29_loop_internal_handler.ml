exception Continue;;
let total = ref 0;;
for i = 0 to 4 do
  try
    if i = 2 then raise Continue else total := !total + i
  with Continue -> ()
done;;
!total;;

