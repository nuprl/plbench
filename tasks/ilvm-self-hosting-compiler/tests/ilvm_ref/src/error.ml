type kind = Io | Usage | Parse | Runtime

exception Error of kind * string

let fail kind message = raise (Error (kind, message))

let message = function
  | Error (_, message) -> message
  | exn -> Printexc.to_string exn
