#! /bin/bash

make
rm -rf newque
mkdir newque
cp _build/tmp/newque.native newque/newque
cp -R lib newque
cp -R conf newque
patchelf --set-rpath '$ORIGIN/lib/' newque/newque
tar czvf newque.0.0.3.tar.gz newque/
echo 'Done'
