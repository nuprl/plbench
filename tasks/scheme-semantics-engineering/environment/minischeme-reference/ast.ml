type t =
  | Int of int
  | Bool of bool
  | String of string
  | Symbol of string
  | List of t list
  | Vector of t array

exception Parse_error of string
exception Static_error of string
exception Runtime_error of string
