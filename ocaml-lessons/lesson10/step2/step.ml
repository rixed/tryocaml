fun input output ->
  find_in "module N1 : sig " output &&
  find_in "val zero : int" output &&
  find_in "val add : int -> int -> int" output
