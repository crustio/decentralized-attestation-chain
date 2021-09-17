#!/usr/bin/env bash
function verbose()
{
    local type=$1
    local info=$2
    local tips=$3
    local color=$GREEN
    local nc=$NC
    local opt="-e"
    local content=""
    local time="[$(date "+%Y/%m/%d %T.%3N")]"

    case $type in
        ERROR)  color=$HRED ;;
        WARN)   color=$YELLOW ;;
        INFO)   color=$GREEN ;;
    esac
    case $tips in 
        h)      
            opt="-n"
            content="$time [$type] $info"
            ;;
        t)      
            opt="-e"
            content="${color}$info${nc}"
            ;;
        n)
            content="$time [$type] $info"
            ;;
        *)
            content="${color}$time [$type] $info${nc}"
    esac
    echo $opt $content
}

function checkRes()
{
    ### receive 4 parameters at most:
    ### $1 : Command execution result
    ### $2 : Should be "return" or "quit", 
    ###      which means if command failed, function returns or process exits
    ### $3 : Success information, which means if command executes successfully, print this info
    ### $4 : Output stream, default is standard output stream
    local res=$1
    local err_op=$2
    local tag=$3
    local descriptor=$4
    local tagfailed=""
    local tagsuccess=""

    if [ x"$descriptor" = x"" ] ; then 
        descriptor="&1"
    fi

    if [ x"$tag" = x"yes" ]; then
        tagsuccess="yes"
        tagfailed="no"
    elif [ x"$tag" = x"success" ]; then
        tagsuccess="success"
        tagfailed="failed"
    fi

    if [ $res -ne 0 ]; then
        eval "verbose ERROR "$tagfailed" t >$descriptor"
    else
        eval "verbose INFO "$tagsuccess" t >$descriptor"
    fi

    while [ -s "$descriptor" ]; do
        sleep 1
    done

    if [ $res -ne 0 ]; then
        case $err_op in
            quit)       
                verbose ERROR "Unexpected error occurs!Please check $ERRFILE for details!"
                exit 1
                ;;
            return)     
                return 1
                ;;
            *)  ;;
        esac
    fi
}

function setTimeWait()
{
    ### Be careful that this function should be used with checkRes function!
    local info=$1
    local syncfile=$2
    local acc=1
    while [ ! -s "$syncfile" ]; do
        printf "%s\r" "${info}${acc}s"
        ((acc++))
        sleep 1
    done

    echo "${info}$(cat $syncfile)"
    true > $syncfile
}
# basice
utildir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
configfile=$utildir/../Config.json
# color
RED='\033[0;31m'
HRED='\033[1;31m'
GREEN='\033[0;32m'
HGREEN='\033[1;32m'
YELLOW='\033[0;33m'
HYELLOW='\033[1;33m'
NC='\033[0m'
# PCCS
instTimeout=600
pccs_service=sgx-dcap-pccs
pcs_api_key=5e0d868dea9c450a886ce6c46913643e
pccs_passwd=Test192837465?
pccs_port=9999
node_lv=v10.0.0
# DCAP server
app_name=dcap-service
app_port=1234
# Print
pad="$(printf '%0.1s' ' '{1..4})"
# Get configuration
useconfig=0
if [ -s $configfile ]; then
    if ! which jq &>/dev/null; then
        verbose WARN "jq is not detected, cannot use configure file"
    else
        tmp=$(cat $configfile | jq -r '.app_port')
        if [ x"$tmp" != x"" ]; then
            app_port=$tmp
        fi
        tmp=$(cat $configfile | jq -r '.pcs_api_key')
        if [ x"$tmp" != x"" ]; then
            pcs_api_key=$tmp
        fi
        tmp=$(cat $configfile | jq -r '.pccs_passwd')
        if [ x"$tmp" != x"" ]; then
            pccs_passwd=$tmp
        fi
        tmp=$(cat $configfile | jq -r '.pccs_port')
        if [ x"$tmp" != x"" ]; then
            pccs_port=$tmp
        fi
        useconfig=1
    fi
fi

if [ $useconfig -eq 0 ]; then
    verbose WARN "use default configuration:"
    verbose INFO "app_port: $app_port" n
    verbose INFO "pcs_api_key: $pcs_api_key" n
    verbose INFO "pccs_passwd: $pccs_passwd" n
    verbose INFO "pccs_port: $pccs_port" n
fi
