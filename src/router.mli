open Core.Std

type t = { table : Channel.t list String.Table.t; }

val create : Watcher.listener list -> t
