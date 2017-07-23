open Core
open Lwt
open Redis_lwt

module Logger = Log.Make (struct let section = "Redis_pubsub" end)

type redis_pubsub_t = {
  pool: Redis_lwt.Client.connection Lwt_pool.t;
  chan_name: string;
  host: string;
  port: int;
  auth: string option;
  database: int;
  broadcast: string;
}

let create ~chan_name host port ~auth ~database ~pool_size ~broadcast =
  let pool = Redis_shared.get_conn_pool host port ~auth ~database ~pool_size ~info:Logger.info in
  let instance = {
    pool;
    chan_name;
    host;
    port;
    auth;
    database;
    broadcast;
  }
  in
  return instance

module M = struct

  type t = redis_pubsub_t

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Zmq_obj_types in
    let open Zmq_obj_pb in

    let input = { channel = instance.chan_name; action = Write_input { atomic = None; ids = (Collection.to_list ids |> snd); } } in
    let input_encoder = Pbrt.Encoder.create () in
    encode_input input input_encoder;
    let encoded_input = Pbrt.Encoder.to_bytes input_encoder in

    let many = { buffers = encoded_input::(Collection.to_list msgs |> snd) } in
    let many_encoder = Pbrt.Encoder.create () in
    encode_many many many_encoder;
    let encoded_many = Pbrt.Encoder.to_bytes many_encoder in

    Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = Client.publish conn instance.broadcast encoded_many in
      return (Collection.length msgs)
    )

  let pull instance ~search ~fetch_last = fail (Exception.Public_exn "Invalid operation on this channel (READ)")

  let size instance = fail (Exception.Public_exn "Invalid operation on this channel (SIZE)")

  let delete instance = fail (Exception.Public_exn "Invalid operation on this channel (DELETE)")

  let health instance = Lwt_pool.use instance.pool (fun conn ->
      let%lwt replies = Client.pubsub_numsub conn [instance.broadcast] in
      match replies with
      | reply_broadcast::reply_count::_ ->
        begin match (reply_broadcast, reply_count) with
          | (`Bulk (Some x)), (`Int _) when String.(=) x instance.broadcast -> return []
          | _ -> return [
              sprintf "Invalid values returned by Redis [%s]"
                (Redis_shared.debug_reply (`Multibulk [reply_broadcast; reply_count]))
            ]
        end
      | values ->
        return [sprintf "Invalid number of values returned by Redis [%d]" (List.length values)]
    )

end
