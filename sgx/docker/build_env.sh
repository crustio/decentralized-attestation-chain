#! /usr/bin/env bash
# script to build dcap service base image

usage() {
    echo "Usage:"
        echo "    $0 -h                      Display this help message."
        echo "    $0 [options]"
    echo "Options:"
    echo "     -p publish image"

    exit 1;
}

PUBLISH=0

while getopts ":hp" opt; do
    case ${opt} in
        h)
            usage
            ;;
        p)
            PUBLISH=1
            ;;
        ?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

basedir=$(cd `dirname $0`;pwd)
instdir=$basedir/..

VER=$(cat $instdir/VERSION | head -n 1)
IMAGEID="crustio/dcap-service-env:$VER"
echo "building $IMAGEID image"
if [ "$PUBLISH" -eq "1" ]; then
  echo "will publish after build"
fi


cd $instdir
docker build -f docker/env/Dockerfile -t $IMAGEID .
if [ "$?" -ne "0" ]; then
  echo "$IMAGEID build failed!"
  exit 1
fi
cd -

echo "build success"
if [ "$PUBLISH" -eq "1" ]; then
  echo "will publish $IMAGEID image"
  docker push $IMAGEID
fi
