## Compile
```bash
sudo apt-get update
sudo apt-get install libev4 libev-dev build-essential libsqlite3-dev

git clone git@github.com:SGrondin/newque.git
opam update
opam switch 4.02.3
opam install atdgen cohttp conf-libev core lwt-zmq oasis ocp-indent ppx_deriving_protobuf sqlite3 utop uuidm

git clone git@github.com:SGrondin/ocaml-conduit.git conduit.0.12.0
# This will reinstall conduit and cohttp
opam pin add conduit conduit.0.12.0

oasis setup
./configure

# To remove some invalid warnings
echo 'export OCAMLFIND_IGNORE_DUPS_IN=/home/nomaddo/.opam/4.03.0/lib/ocaml/compiler-libs/' >> ~/.bashrc
source ~/.bashrc

make
```

## Tests
```bash
cd test
npm install

npm test
```
