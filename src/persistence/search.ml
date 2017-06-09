open Core

type after =
  | After_id of string
  | After_ts of int64
  | After_rowid of int64

type t = {
  limit: int64;
  after: after option;
  only_once: bool;
}

let create max_read ~mode ~only_once =
  match mode with
  | `One ->
    {
      limit = Int64.one;
      after = None;
      only_once;
    }
  | `Many x ->
    {
      limit = Int64.min max_read x;
      after = None;
      only_once;
    }
  | `After_id id ->
    {
      limit = max_read;
      after = Some (After_id id);
      only_once;
    }
  | `After_ts ts ->
    {
      limit = max_read;
      after = Some (After_ts ts);
      only_once;
    }

let mode_and_limit search = match search with
  | { after = Some (After_id id); limit; } -> ((`After_id id), limit)
  | { after = Some (After_ts ts); limit; } -> ((`After_ts ts), limit)
  | { limit; _ } -> ((`Many limit), limit)
