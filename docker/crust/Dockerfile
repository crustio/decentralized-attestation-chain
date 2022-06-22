# Build crust image
FROM ubuntu:20.04

RUN apt-get update
RUN apt-get install -y openssl ca-certificates
COPY crust /opt/crust/crust
COPY run.sh /opt/run.sh

WORKDIR /opt/crust/
CMD /opt/run.sh
