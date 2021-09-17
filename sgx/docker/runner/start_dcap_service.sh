#!/bin/bash
. /dcap-service/scripts/utils.sh
pccs_conf_file=/opt/intel/sgx-dcap-pccs/config/default.json
sgx_qcnl_conf_file=/etc/sgx_default_qcnl.conf
# Check if there is new configuration
if [ x"$PCCS_PORT" != x"" ]; then
    sed -i "/\"HTTPS_PORT\"/ c \    \"HTTPS_PORT\" : $PCCS_PORT," $pccs_conf_file
    sed -i "s@$pccs_port@$PCCS_PORT@g" $sgx_qcnl_conf_file
    pccs_port=$PCCS_PORT
fi
if [ x"$PCS_API_KEY" != x"" ]; then
    sed -i "/\"ApiKey\"/ c \    \"ApiKey\" : \"$PCS_API_KEY\"," $pccs_conf_file
fi
cd /opt/intel/sgx-dcap-pccs
nohup node -r esm pccs_server.js &>/dev/null &
pid=$!
cd - &>/dev/null

sleep 10
if ! lsof -i :$pccs_port | grep $pid &>/dev/null; then
    verbose ERROR "start pccs service failed! Please check if another process is occupying port $pccs_port"
    exit 1
fi

# Start dcap service
/opt/crust/tools/bin/dcap-service $DCAP_ARGS
