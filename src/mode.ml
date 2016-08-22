module Pub = struct
  type t = [
    | `Single
    | `Multiple
    | `Atomic
  ]
end

module Sub = struct
  type t = [
    | `One
    | `Upto of int
  ]
end

module Pubsub = struct
  type t = [ Pub.t | Sub.t ]
end

type t = [
  | `Pub of Pub.t
  | `Sub of Sub.t
]
