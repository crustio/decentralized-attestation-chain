#!/bin/bash
function installDeps()
{
    # Basic lib
    checkAndInstall "${basic_deps[*]}"

    # Update source
    if ! grep "$(echo $sgx_repo | awk '{print $3}')" $sgx_repo_file &>/dev/null; then
        verbose INFO "Adding resource list..." h
        echo $sgx_repo | tee $sgx_repo_file &>>$ERRFILE
        checkRes $? "quit" "success"
        verbose INFO "Adding apt key..." h
	    wget -qO - $sgx_apt_key | apt-key add - &>>$ERRFILE
        checkRes $? "quit" "success"

        > $SYNCFILE
        setTimeWait "$(verbose INFO "Updating..." h)" $SYNCFILE &
        toKillPID[${#toKillPID[*]}]=$!
        apt-get update &>>$ERRFILE
        checkRes $? "quit" "success" "$SYNCFILE"
    fi

    # Check node version
    verbose INFO "Check nodejs..." h
    local cur_nv=$(node --version 2>/dev/null)
    local new_nv=$(echo -e "${node_lv}\n${cur_nv}" | sort -t . -n -k1 -k2 -k3 -r | head -n 1)
    if [ x"$new_nv" = x"$node_lv" ]; then
        verbose ERROR "no" t
        verbose INFO "node version should be newer than $node_lv, would install node16"
        > $SYNCFILE
        setTimeWait "$(verbose INFO "Installing node16..." h)" $SYNCFILE &
        toKillPID[${#toKillPID[*]}]=$!
        apt-get install -y curl dirmngr apt-transport-https lsb-release ca-certificates &>>$ERRFILE
        curl -sL https://deb.nodesource.com/setup_16.x | bash - &>>ERRFILE
        apt-get install -y nodejs &>>$ERRFILE
        checkRes $? "quit" "success" "$SYNCFILE"
    else
        verbose INFO "yes" t
    fi

    # PCCS service deps
    checkAndInstall "${pccs_deps[*]}"

    # For dev
    checkAndInstall "${ecdsa_dev_deps[*]}"
}

function installOPENSSL()
{
    # Check openssl
    verbose INFO "Checking openssl..." h
    if [ -d $crusttoolsdir/openssl ]; then
        verbose INFO "yes" t
        return 0
    fi
    verbose ERROR "no" t

    # Download openssl
    if [ ! -s $rsrcdir/$opensslpkg ]; then
        wget -P $rsrcdir $openssl_url
        if [ $? -ne 0 ]; then
            verbose ERROR "Download openssl from $openssl_url failed!"
            exit 1
        fi
    fi

    # Install openssl
    > $SYNCFILE
    setTimeWait "$(verbose INFO "Installing openssl..." h)" $SYNCFILE &
    toKillPID[${#toKillPID[*]}]=$!
    local openssl_pkg_name=$(tar tzf $rsrcdir/$opensslpkg | sed -e 's@/.*@@'  | uniq)
    tar -xzf $rsrcdir/$opensslpkg -C $tmpdir
    cd $tmpdir/$openssl_pkg_name
    ./config --prefix=$crusttoolsdir/openssl &>/dev/null
    make -j8 &>>$ERRFILE
    if [ $? -ne 0 ]; then
        verbose ERROR "no" t
        exit 1
    fi
    make install &>>$ERRFILE
    checkRes $? "quit" "success" "$SYNCFILE"
    cd - &>/dev/null
}

function installSGXSDK()
{
    # Check SGX SDK
    verbose INFO "Checking SGX SDK..." h
    if [ -d $sgxsdkdir ]; then
        verbose INFO "yes" t
        return 0
    fi
    verbose ERROR "no" t

    # Download sgx sdk
    if [ ! -s $rsrcdir/$sdkpkg ]; then
        wget -P $rsrcdir $sdkpkg_url
        if [ $? -ne 0 ]; then
            verbose ERROR "Download SGX SDK from $sdkpkg_url failed!"
            exit 1
        fi
        chmod +x $rsrcdir/$sdkpkg
    fi

    # Install SGX SDK
    local res=0
    cd $rsrcdir
    verbose INFO "Installing SGX SDK..." h
    if [ -f "$inteldir/sgxsdk/uninstall.sh" ]; then
        $inteldir/sgxsdk/uninstall.sh &>$ERRFILE
        res=$(($?|$res))
    fi

    # Install
expect << EOF > $TMPFILE
    set timeout $instTimeout
    spawn $rsrcdir/$sdkpkg
    expect "yes/no"          { send "no\n"  }
    expect "to install in :" { send "$inteldir\n" }
    expect eof
EOF
    cat $TMPFILE | grep successful &>/dev/null
    res=$(($?|$res))
    cd - &>/dev/null

    checkRes $res "quit" "success"
}

function installPCCS()
{
    verbose INFO "Checking PCCS..." h
    service pccs start &>>$ERRFILE
    if [ $? -eq 0 ]; then
        verbose INFO "yes" t
        return 0
    fi
    verbose ERROR "no" t

    > $SYNCFILE
    setTimeWait "$(verbose INFO "Installing PCCS..." h)" $SYNCFILE &
    toKillPID[${#toKillPID[*]}]=$!
    if [ x"$WITHDOCKER" = x"1" ]; then
        mkdir -p /etc/init
    fi
expect << EOF >> $ERRFILE
    set timeout $instTimeout
    spawn apt-get install -y $pccs_service
    expect "install PCCS now? (Y/N)"          { send "Y\n" }
    expect "Enter your http proxy server address"          { send "\n" }
    expect "Enter your https proxy server address"          { send "\n" }
    expect "configure PCCS now"          { send "Y\n" }
    expect "Set HTTPS listening port"          { send "$pccs_port\n" }
    expect "Set the PCCS service to accept local connections only"          { send "N\n" }
    expect "Set your Intel PCS API key"          { send "$pcs_api_key\n" }
    expect "Choose caching fill method"          { send "LAZY\n" }
    expect "Set PCCS server administrator password"          { send "$pccs_passwd\n" }
    expect "Re-enter administrator password"          { send "$pccs_passwd\n" }
    expect "Set PCCS server user password"          { send "$pccs_passwd\n" }
    expect "Re-enter user password"          { send "$pccs_passwd\n" }
    expect "generate insecure HTTPS key and cert for PCCS service"          { send "Y\n" }
    expect "Country Name"          { send "\n" }
    expect "State or Province Name (full name)"          { send "\n" }
    expect "Locality Name"          { send "\n" }
    expect "Organization Name"          { send "\n" }
    expect "Organizational Unit Name"          { send "\n" }
    expect "Common Name"          { send "\n" }
    expect "Email Address"          { send "\n" }
    expect "A challenge password"          { send "Test1234\n" }
    expect "An optional company name"          { send "crust\n" }
    expect eof
EOF
    local res=0
    if [ x"$WITHDOCKER" != x"1" ]; then
        sleep 3
        lsof -i :$pccs_port &>>$ERRFILE
        res=$?
    fi
    checkRes $res "quit" "success" "$SYNCFILE"
}

function checkAndInstall()
{
    for dep in $1; do
        verbose INFO "Checking $dep..." h
        if dpkg -l | grep " ${dep} " &>/dev/null; then
            verbose INFO "yes" t
            continue
        fi
        verbose ERROR "no" t
        verbose INFO "Installing $dep..." h
        apt-get install -y $dep &>>$ERRFILE
        if [ $? -ne 0 ]; then
            verbose ERROR "failed" t
            exit 1
        fi
        verbose INFO "success" t
    done
}

function success_exit()
{
    rv=$?
    if [ $rv -ne 0 ]; then
        tail -n 20 $ERRFILE
    fi

    rm -rf $tmpdir &>/dev/null
    rm $SYNCFILE &>/dev/null
    rm $TMPFILE &>/dev/null

    # Kill alive useless sub process
    for el in ${toKillPID[@]}; do
        if ps -ef | grep -v grep | grep $el &>/dev/null; then
            kill -9 $el
        fi
    done
}

##### MAIN BODY #####
# Base directory
basedir=$(cd `dirname $0`;pwd)
instdir=$basedir/..
rsrcdir=$instdir/resource
openssl_url="https://ftp.openssl.org/source/old/1.1.1/openssl-1.1.1g.tar.gz"
sdkpkg_url="https://download.01.org/intel-sgx/sgx-linux/2.11/distro/ubuntu18.04-server/sgx_linux_x64_sdk_2.11.100.2.bin"
opensslpkg=openssl-1.1.1g.tar.gz
sdkpkg=sgx_linux_x64_sdk_2.11.100.2.bin
crustdir=/opt/crust
crusttoolsdir=$crustdir/tools
crustlogdir=$crustdir/log
dcaplogfile=$crustlogdir/dcap.log
tmpdir=$instdir/tmp
ERRFILE=$instdir/err.log
SYNCFILE=$basedir/.syncfile
toKillPID=()
TMPFILE=$basedir/tmp.$$
# Intel
inteldir=/opt/intel
sgxsdkdir=$inteldir/sgxsdk
# Dependency
sgx_repo='deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu bionic main'  
sgx_repo_file=/etc/apt/sources.list.d/intel-sgx.list
sgx_apt_key=https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key
basic_deps=(curl wget jq lsof build-essential python expect linux-headers-`uname -r`)
pccs_deps=(libsgx-urts libsgx-dcap-ql libsgx-dcap-default-qpl libsgx-dcap-quote-verify)
ecdsa_dev_deps=(libsgx-enclave-common-dev libsgx-dcap-ql-dev libsgx-dcap-default-qpl-dev libsgx-dcap-quote-verify-dev)

. $basedir/utils.sh
true > $ERRFILE

mkdir -p $tmpdir
mkdir -p $crustdir
mkdir -p $crusttoolsdir
mkdir -p $crustlogdir
mkdir -p $rsrcdir

trap "success_exit" EXIT

WITHDOCKER=0
if [ x"$1" != x"" ]; then
    WITHDOCKER=$1
fi

if [ $(id -u) -ne 0 ]; then
    verbose ERROR "Please run with sudo!"
    exit 1
fi

# Install dependency
installDeps

# Install openssl
installOPENSSL

# Install openssl
installSGXSDK

# Install PCCS
installPCCS
