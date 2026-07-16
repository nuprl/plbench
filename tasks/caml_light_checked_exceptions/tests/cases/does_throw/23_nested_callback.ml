exception Fold_error;;
let fold f init values = list__it_list f init values;;
fold (fun acc x -> if x = 3 then raise Fold_error else acc + x)
     0 [1; 2; 3; 4];;

