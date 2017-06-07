open Core

type t = {
  limit: int64;
  after_id: string option;
  after_ts: int64 option;
  after_rowid: int64 option;
  only_once: bool;
}

let create max_read ~mode ~only_once =
  match mode with
  | `One ->
    {
      limit = Int64.one;
      after_id = None;
      after_ts = None;
      after_rowid = None;
      only_once;
    }
  | `Many x ->
    {
      limit = Int64.min max_read x;
      after_id = None;
      after_ts = None;
      after_rowid = None;
      only_once;
    }
  | `After_id id ->
    {
      limit = max_read;
      after_id = Some id;
      after_ts = None;
      after_rowid = None;
      only_once;
    }
  | `After_ts ts ->
    {
      limit = max_read;
      after_id = None;
      after_ts = Some ts;
      after_rowid = None;
      only_once;
    }

let has_any_filters search = match search with
  | { after_id = None; after_ts = None; after_rowid = None; } -> false
  | _ -> true

let mode_and_limit search = match search with
  | { after_id = Some id; limit; } -> ((`After_id id), limit)
  | { after_ts = Some ts; limit; } -> ((`After_ts ts), limit)
  | { limit; _ } -> ((`Many limit), limit)
