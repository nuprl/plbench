exception Map_callback_error;;
list__map (fun _ -> raise Map_callback_error) [1];;

