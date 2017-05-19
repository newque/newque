#!/bin/bash

#need to turn off globbing

echo "THIS SCRIPT SHOULD BE RUN FROM THE ROOT DIRECTORY"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++"

TAG_VER_OLD="$(git ls-remote --tags --refs ssh://git@github.com/SGrondin/newque.git | awk -F/ '{ print $3 }'| tail -n2 | head -1)"
VER_OLD=${TAG_VER_OLD//v}
TAG_VERSION="$(git ls-remote --tags --refs ssh://git@github.com/SGrondin/newque.git | awk -F/ '{ print $3 }'| tail -n1)"
VERSION=${TAG_VERSION//v}

echo "UPDATING FROM $VER_OLD TO $VERSION"
echo "==="

echo "UPDATING _oasis"
sed -i "s/${VER_OLD}/${VERSION}/g" _oasis

echo "UPDATING scripts/release.sh"
sed -i "s/${VER_OLD}/${VERSION}/g" scripts/release.sh

echo "UPDATING docker/Dockerfile"
sed -i "s/${VER_OLD}/${VERSION}/g" docker/Dockerfile
# This approach was problematic due to globbing, i.e. * expansion
#while read -r a ; do echo ${a//$VER_OLD/$VERSION} ; done < docker/Dockerfile > docker/Dockerfile.t ; 
#    mv docker/Dockerfile.t docker/Dockerfile
echo "UPDATING src/newque.ml"
sed -i "s/${VER_OLD}/${VERSION}/g" src/newque.ml