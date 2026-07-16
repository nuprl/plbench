try
  let table = hashtbl__new 7 in
  hashtbl__find table "missing"
with Invalid_argument _ -> 0 | Not_found -> 0;;
