#!/bin/bash
function installAPP()
{
    if lsof -i :$app_port &>/dev/null; then
        if lsof -i :$app_port | grep "${app_name:0:len-1}" &>/dev/null; then
            verbose INFO "$app_name is running."
        else
            verbose ERROR "Port $app_port has been occupied, another process takes this port."
            exit 1
        fi
        return 0
    fi

    > $SYNCFILE
    setTimeWait "$(verbose INFO "Installing APP..." h)" $SYNCFILE &
    toKillPID[${#toKillPID[*]}]=$!
    cd $instdir/src
    make clean
    make &>>$ERRFILE
    checkRes $? "quit" "success" "$SYNCFILE"
    mkdir -p $crusttoolsdir/bin
    cp $app_name $crusttoolsdir/bin
    # Configure PCCS
    sed -i "/pccs_url/ c \ \ \"pccs_url\": \"https://localhost:$pccs_port/sgx/certification/v3/\"," /etc/sgx_default_qcnl.conf
    sed -i '/use_secure_cert/ c \ \ "use_secure_cert": false,' /etc/sgx_default_qcnl.conf
}

function success_exit()
{
    rv=$?

    rm -rf $tmpdir &>/dev/null
    rm $SYNCFILE &>/dev/null

    # Kill alive useless sub process
    for el in ${toKillPID[@]}; do
        if ps -ef | grep -v grep | grep $el &>/dev/null; then
            kill -9 $el
        fi
    done

    if [ $rv -eq 0 ]; then
        printEnd_success
    else
        printEnd_failed
    fi
}

function printEnd_success()
{
    printf "%s%s\n"   "$pad" '    _            __        ____                  __'
    printf "%s%s\n"   "$pad" '   (_)___  _____/ /_____ _/ / /  ___  ____  ____/ /'
    printf "%s%s\n"   "$pad" '  / / __ \/ ___/ __/ __ `/ / /  / _ \/ __ \/ __  / '
    printf "%s%s\n"   "$pad" ' / / / / (__  ) /_/ /_/ / / /  /  __/ / / / /_/ /  '
    printf "%s%s\n\n" "$pad" '/_/_/ /_/____/\__/\__,_/_/_/   \___/_/ /_/\__,_/   '
}

function printEnd_failed()
{
    printf "%s${HRED}%s${NC}\n"   "$pad" '    _            __        ____    ____      _ __         __'
    printf "%s${HRED}%s${NC}\n"   "$pad" '   (_)___  _____/ /_____ _/ / /   / __/___ _(_) /__  ____/ /'
    printf "%s${HRED}%s${NC}\n"   "$pad" '  / / __ \/ ___/ __/ __ `/ / /   / /_/ __ `/ / / _ \/ __  / '
    printf "%s${HRED}%s${NC}\n"   "$pad" ' / / / / (__  ) /_/ /_/ / / /   / __/ /_/ / / /  __/ /_/ /  '
    printf "%s${HRED}%s${NC}\n\n" "$pad" '/_/_/ /_/____/\__/\__,_/_/_/   /_/  \__,_/_/_/\___/\__,_/   '
}

##### MAIN BODY #####
# Base directory
basedir=$(cd `dirname $0`;pwd)
instdir=$basedir/..
crustdir=/opt/crust
crusttoolsdir=$crustdir/tools
crustlogdir=$crustdir/log
dcaplogfile=$crustlogdir/dcap.log
tmpdir=$instdir/tmp
ERRFILE=$instdir/err.log
SYNCFILE=$basedir/.syncfile
toKillPID=()

. $basedir/utils.sh
true > $ERRFILE


printf "%s%s\n"   "$pad" '    _            __        ____    ____  ____  ___       _____ __________ _    ____________ '
printf "%s%s\n"   "$pad" '   (_)___  _____/ /_____ _/ / /   / __ \/ __ \/   |     / ___// ____/ __ \ |  / / ____/ __ \'
printf "%s%s\n"   "$pad" '  / / __ \/ ___/ __/ __ `/ / /   / /_/ / / / / /| |     \__ \/ __/ / /_/ / | / / __/ / /_/ /'
printf "%s%s\n"   "$pad" ' / / / / (__  ) /_/ /_/ / / /   / ____/ /_/ / ___ |    ___/ / /___/ _, _/| |/ / /___/ _, _/ '
printf "%s%s\n\n" "$pad" '/_/_/ /_/____/\__/\__,_/_/_/   /_/    \____/_/  |_|   /____/_____/_/ |_| |___/_____/_/ |_|  '


mkdir -p $tmpdir
mkdir -p $crustdir
mkdir -p $crusttoolsdir
mkdir -p $crustlogdir

trap "success_exit" EXIT

WITHDOCKER=0
while getopts "d" opt; do
    case ${opt} in 
        d)
            WITHDOCKER=1
            ;;
        ?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

if [ $(id -u) -ne 0 ]; then
    verbose ERROR "Please run with sudo!"
    exit 1
fi

if [ $WITHDOCKER -eq 0 ] && ! lsof -i :$pccs_port | grep pccs &>/dev/null; then
    # Install deps
    $basedir/install_deps.sh $WITHDOCKER
fi

# Install app
installAPP
