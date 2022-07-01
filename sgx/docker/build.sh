#! /usr/bin/env bash
# build dcap service docker image

usage() {
    echo "Usage:"
        echo "    $0 -h                      Display this help message."
        echo "    $0 [options]"
    echo "Options:"
    echo "     -p publish image"

    exit 1;
}

PUBLISH=0
genyaml=0

while getopts ":hpg" opt; do
    case ${opt} in
        h)
            usage
            ;;
        p)
            PUBLISH=1
            ;;
        g)
            genyaml=1
            ;;
        ?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

basedir=$(cd `dirname $0`;pwd)
instdir=$basedir/..
scriptsdir=$instdir/scripts

. $scriptsdir/utils.sh

VER=$(cat $instdir/VERSION | head -n 1)
IMAGEID="crustio/dcap-service:$VER"

echo "building dcap service runner image $IMAGEID"
if [ "$PUBLISH" -eq "1" ]; then
    echo "will publish after build"
fi

cd $instdir
make clean
docker build -f docker/runner/Dockerfile -t $IMAGEID .
if [ "$?" -ne "0" ]; then
    echo "$IMAGEID build failed!"
    exit 1
fi
cd -

echo "crustio/dcap-service build success"
if [ "$PUBLISH" -eq "1" ]; then
    echo "will publish image to $IMAGEID"
    docker push $IMAGEID
fi

if [ $genyaml -eq 1 ]; then
    builddir=/opt/crust/build
    mkdir -p $builddir
cat << EOF > $builddir/docker-compose.yaml
version: '2.0'
services:
  dcap-service:
    image: '$IMAGEID'
    network_mode: host
    container_name: dcap-service
    environment:
      DCAP_ARGS: '-t 0.0.0.0 -p $app_port'
      PCCS_PORT: '$pccs_port'
      PCS_API_KEY: '$pcs_api_key'
EOF
    echo
    verbose INFO "Generate docker-compose.yaml at $builddir/docker-compose.yaml successfully!"
    verbose INFO "You can check and start DCAP service by running 'sudo docker-compose up dcap-service'"
    echo
fi
