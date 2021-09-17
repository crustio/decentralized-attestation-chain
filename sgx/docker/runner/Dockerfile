# crust sworker image
FROM crustio/dcap-service-env:1.0.0

ADD scripts /dcap-service/scripts
ADD src /dcap-service/src
ADD VERSION /dcap-service/VERSION
ADD Makefile /dcap-service/Makefile
ADD Config.json /dcap-service/Config.json
RUN /dcap-service/scripts/install.sh -d
ADD docker/runner/start_dcap_service.sh /
CMD /start_dcap_service.sh $ARGS
