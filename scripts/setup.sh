#! /bin/bash

# Remove Oasis files
rm -f myocamlbuild.ml setup.data setup.ml _tags Makefile

# Create new Oasis files
oasis setup
./configure

# Keep a copy of the stubs
cp tmp/libnewque_stubs.clib .
