## Compile

Don't run as `root`. Instructions for Debian/Ubuntu.
```bash
sudo apt-get update
sudo apt-get install libev4 libev-dev build-essential libsqlite3-dev liblua5.1-0 liblua5.1-0-dev patchelf aspcud opam libtool pkg-config autoconf automake uuid-dev

# Then install ZeroMQ 4.0.x using the "To build on UNIX-like systems" instructions at
# http://zeromq.org/intro:get-the-software

opam init
# Pay attention and run "eval `opam config env`" whenever OPAM asks for it.
opam update
opam switch 4.04.2+flambda

git clone https://github.com/newque/newque.git
cd newque

opam install atdgen cohttp conf-libev core cppo lwt-zmq oasis ocaml-protoc ocp-indent pla ppx_deriving_protobuf redis-lwt sqlite3 utop uuidm -y

git clone https://github.com/SGrondin/ocaml-lua.git newque-lua
opam pin add ocaml-lua newque-lua -y

git clone https://github.com/SGrondin/ocaml-conduit.git newque-conduit
opam pin add conduit newque-conduit -y

# Downloads some dependencies and runs 'configure' scripts
./scripts/setup.sh

# Compile
make
```

## Tests

Must have Node.js, Redis and Elasticsearch installed locally.
Don't run the tests if you have important data stored in Redis or ES!
```bash
cd test
npm install

npm test
```
