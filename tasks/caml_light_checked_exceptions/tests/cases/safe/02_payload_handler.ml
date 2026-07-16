exception Payload of int;;
try raise (Payload 8) with Payload n -> n + 1;;

