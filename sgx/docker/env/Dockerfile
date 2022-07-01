# crust dcap-service env image
FROM ubuntu:18.04

# install build depends
RUN apt-get update
RUN apt-get install -y wget expect unzip jq cracklib-runtime
ADD scripts /dcap-service-env/scripts
ADD Config.json /dcap-service-env/Config.json
RUN /dcap-service-env/scripts/install_deps.sh 1
