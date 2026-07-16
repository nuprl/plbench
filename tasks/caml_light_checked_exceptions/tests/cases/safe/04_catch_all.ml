exception Hidden of string;;
try raise (Hidden "caught") with _ -> ();;

