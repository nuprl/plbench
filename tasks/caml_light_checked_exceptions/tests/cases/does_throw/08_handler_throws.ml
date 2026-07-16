exception Body_error;;
exception Handler_error;;
try raise Body_error with Body_error -> raise Handler_error;;

