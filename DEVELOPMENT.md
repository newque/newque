## Compile

Don't run as `root`. Instructions for Debian/Ubuntu.
```bash
sudo apt-get update
sudo apt-get install libev4 libev-dev build-essential libsqlite3-dev liblua5.1-0 liblua5.1-0-dev patchelf upx aspcud opam libtool pkg-config autoconf automake uuid-dev

# Then install ZeroMQ 4.0.x using the "To build on UNIX-like systems" instructions at
# http://zeromq.org/intro:get-the-software

opam init
# Pay attention and run "eval `opam config env`" whenever OPAM asks for it.
opam update
opam switch 4.03.0

git clone git@github.com:SGrondin/newque.git
cd newque

git clone git@github.com:SGrondin/ocaml-lua.git newque-lua
opam pin add ocaml-lua newque-lua -y

git clone git@github.com:SGrondin/ocaml-conduit.git newque-conduit
opam pin add conduit newque-conduit -y

opam install atdgen cohttp conf-libev core cppo lwt-zmq oasis ocaml-protoc ocp-indent ppx_deriving_protobuf sqlite3 utop uuidm

# Downloads some dependencies and runs 'configure' scripts
./scripts/setup.sh

# To remove some invalid warnings, run (replace USERNAME in the path):
echo 'export OCAMLFIND_IGNORE_DUPS_IN=/home/USERNAME/.opam/4.03.0/lib/ocaml/compiler-libs/' >> ~/.bashrc
source ~/.bashrc

make
```

## Tests

Must have Node.js and Elasticsearch installed.
```bash
cd test
npm install

npm test
```
