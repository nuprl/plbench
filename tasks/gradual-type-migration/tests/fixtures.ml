type case = {
  name : string;
  program : string;
  context : string option; [@default None]
  maximal_migrations : string list;
}
[@@deriving yaml]

type cases = case list [@@deriving yaml]

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let load path =
  let ( let* ) = Result.bind in
  let parsed =
    let* document = Yaml.of_string (read_file path) in
    cases_of_yaml document
  in
  match parsed with
  | Ok cases -> cases
  | Error (`Msg message) -> failwith ("invalid fixture YAML: " ^ message)
