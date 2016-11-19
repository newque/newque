## Compile

Don't run as `root`.
```bash
sudo apt-get update
sudo apt-get install libev4 libev-dev build-essential libsqlite3-dev opam

opam update
opam switch 4.02.3
opam install atdgen cohttp conf-libev core lwt-zmq oasis ocp-indent ppx_deriving_protobuf sqlite3 utop uuidm

git clone git@github.com:SGrondin/newque.git
# Then, cd into the cloned newque repo and run:
git clone git@github.com:SGrondin/ocaml-conduit.git conduit.0.12.0

# This next command will reinstall conduit and cohttp:
opam pin add conduit conduit.0.12.0

oasis setup
./configure

# To remove some invalid warnings, run (replace USERNAME in the path):
echo 'export OCAMLFIND_IGNORE_DUPS_IN=/home/USERNAME/.opam/4.02.3/lib/ocaml/compiler-libs/' >> ~/.bashrc
source ~/.bashrc

make
```

## Tests

Must have Node.js installed.
```bash
cd test
npm install

npm test
```
