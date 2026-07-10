type t =
  | Int of int
  | Bool of bool
  | String of string
  | Symbol of string
  | List of t list
  | Vector of t array

exception Error of string
