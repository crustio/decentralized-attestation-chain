# DCAP service
This DCAP(Data Center Attestation Primitives) service is used to verify Crust sWorker entry-network identity and returns an identity entry for TEE auth chain to sign.

## Prerequisites 
- Install git-lfs:
  ```
  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
  sudo apt-get install git-lfs
  git lfs install
  ```

- Clone project
  ```
  git clone https://github.com/crustio/tee-auth-chain.git
  ```

## Install & Start
1. Run 'sudo <root_dir>/sgx/scripts/install_deps.sh' to install dependencies
1. Run 'sudo <root_dir>/sgx/scripts/install.sh' to install executable binary:dcap-service to /opt/crust/tools/bin
1. Run '/opt/crust/tools/bin/dcap-service' to start dcap-service, default port is 'localhost:1234', you can use '-t' to indicate host while '-p' is used to specify a port.

## Install & Start with docker
1. Run 'sudo <root_dir>/sgx/docker/build_env.sh' to build DCAP service environment docker
1. Run 'sudo <root_dir>/sgx/docker/build.sh' to build DCAP service docker, adding '-g' option will generate a docker-compose.yaml for you, which looks like:
   ```
   version: '2.0'
   services:
     dcap-service:
       image: 'crustio/dcap-service:1.0.0'
       network_mode: host
       container_name: dcap-service
       environment:
         DCAP_ARGS: '-t localhost -p 17777'
         PCCS_PORT: '9999'
         PCS_API_KEY: '5e0d868dea9c450a886ce6c46913643e'
   ```
- **DCAP_ARGS** indicates DCAP service host and port. It must be localhost:17777 right now.
- **PCCS_PORT** indicates PCCS service port
- **PCS_API_KEY** indicates PCCS service api key

If you want to configure your own PCCS configure, you can map your PCCS configure file to docker container's PCCS configure file located at '/etc/sgx_default_qcnl.conf'. Then, run 'sudo docker-compose up dcap-service' to start DCAP service.
