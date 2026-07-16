exception Deep;;
let leaf x = if x = 0 then raise Deep else x;;
let middle x = leaf (x - 1);;
let outer x = middle x;;
try outer 1 with Deep -> 99;;

