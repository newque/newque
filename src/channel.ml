let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
}
