#! /bin/bash

# Remove Oasis files
rm -rf configure libnewque_stubs.clib Makefile myocamlbuild.ml setup.data setup.ml _tags tmp
mkdir tmp

# Create new Oasis files
oasis setup
./configure

# Remove ocaml-lua's test executable _tags file to avoid useless warnings
rm -f newque-lua/_tags

# Keep a copy of the stubs
cp tmp/libnewque_stubs.clib .

# Download rapidjson if missing
if [ ! -d "rapidjson" ]; then
  echo 'Downloading rapidjson_v1.1.0'
  wget -nv https://github.com/miloyip/rapidjson/archive/v1.1.0.tar.gz -O src/bindings/rapidjson_v1.1.0.tar.gz
  tar xzf src/bindings/rapidjson_v1.1.0.tar.gz
  mv rapidjson-1.1.0/include/rapidjson rapidjson
  rm -rf rapidjson-1.1.0 src/bindings/rapidjson_v1.1.0.tar.gz
fi
echo 'Done'
