#!/bin/bash -e

function usage() {
cat <<EOH
Usage: $0 [ COMMAND ] [ OPTIONS ]

This script is used for CoreNIC projects buildbot configuration, including
creation of buildbot master, docker slaves, job directories etc.

The current working directory is always assumed to be the base of the buildbot
master, even when creating a buildbot instance or service.

Note that there may be additional somewhat unrelated work done in this buildbot
instance too, e.g. the Sprite driver.

COMMANDS:
 -A           Recreate the buildbot configuration with default options.
 -D           Create docker workers (assumes docker is installed).
 -J           Create job directory.
 -M           Create buildbot master instance in current working directory.
 -S           Create systemd service for current master.
 -T           Test docker workers (assumes docker-py is installed).
 -h           This help message

OPTIONS (some only applicable to certain COMMANDS):
 -c COUNT     Set the number of docker workers to generate/test. (Default = 4)
 -j DIR       Set the job directory name. (Default = "job")
 -m NAME      Set the buildbot master name. (Default = ".", assumes already in
              the buildbot base directory)

EOH
exit 1
}

num_workers=4
jobdir="job"
master_name="."
command=""

set_command() {
    if [ -n "$command" ]; then
        echo "Only a single command can be specified!"
        echo
        usage
    fi
    command=$1
}

while getopts "ADJMSThc:j:" opt; do
    case $opt in
        "?") usage;;
        h) usage;;
        A) set_command "all";;
        D) set_command "docker";;
        J) set_command "job";;
        M) set_command "master";;
        S) set_command "service";;
        T) set_command "test_docker";;
        c) num_workers=$OPTARG;;
        j) jobdir=$OPTARG;;
        m) master_name=$OPTARG;;
    esac
done

create_buildbot_master() {
    buildbot create-master -r $master_name
    mkdir -p ./transfers
    mkdir -p ./nti_configs
    mkdir -p ./patches

    echo
    echo "** Created buildmaster with base directory: $(pwd)/$master_name"
    echo "   You may now copy your master.cfg file and start buildbot."
}

create_service() {
    path=$(pwd)/$master_name
    if [ "$master_name" = "." ]; then
        master_name=$(basename $(pwd))
        path=$(pwd)
    fi
    cat <<EOH > /etc/systemd/system/buildbot_${master_name}.service
[Unit]
Description=CoreNIC Buildbot Service

[Service]
Type=simple
WorkingDirectory=$path
ExecStart=/usr/local/bin/buildbot start
ExecReload=/usr/local/bin/buildbot reconfig
ExecStop=/usr/local/bin/buildbot stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOH
    chmod 664 /etc/systemd/system/buildbot_${master_name}.service
    systemctl daemon-reload
    systemctl enable buildbot_${master_name}.service

    echo
    echo "** Generated buildbot_${master_name} service and enabled it."
    echo "   You may use the following commands to start, stop or reload:"
    echo "     $ service buildbot_${master_name} start"
    echo "     $ service buildbot_${master_name} stop"
    echo "     $ service buildbot_${master_name} reload"
}

create_docker_workers() {
    cat <<EOH > /tmp/docker_key
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAubYKfX2oBKf5OAdW6n8LkgFL1P6VDheRfa3K5LgpZKV82JPe
KULlynyZVuaSbAU87/wOUt/fK4EYQPlrH0r7uSdtB3JidwbZ0Oaoa8UoarlYd/Hg
jya7+ygFQ1HsMbdCqxFaoSvMgHZ9U/Ka5VYgzVaOFXnbS+vDAc04GQOFq47f3rRn
LYOzAic9YdEXat0VI3PgUNay5+5fhNQiPN1JSTXv46dpWdSA455Np3xxJctDDuEk
krEFw1x2Nj8qmkpmRD0noZGibSJpfUGrq1ThsG91bmhyUaxs0nOUaahUd8WyN4eG
64GzSYe4a6fpy1Imbf3YHjY+2ANof38/3EK7CwIDAQABAoIBAC77gwPkelFTPZWT
JcYFhiPV+B1WmtcJ12D4StA6Vx6DT2ZrYlUF+6SSiSiXBIwXdycvmWAWCxuyeTRW
5WbxTWW2N7sekRKTxR84e3toUaVOZrdRlgIhRoVvxoUVgK/DMTaeGVOVBROq5mIK
im1isMHCGAgO4BABAUC/bmXFoleYSxVpKNXRb2PCGiK0uSXU0CKRXL6N2T1yBdZC
tDus09GcCvrxFB3X///ZM25r4mY8yErUy6wkia1SVn3gIan9ER4sC3z7LYbegaEM
fGytLbai9lVe/oKe8+wfYnbXj2YH8rTayiZXn3NSYKSlYW9HV60hEsaH6KhxQXY0
IPgUx2ECgYEA7C2GA+c1fv/sqFfB4VtepFNoDQdS1c4Y8E77yYIylIws5vua86bM
Xbk1mlPwD4mrvf+V6GGUfAda2oytQXJcy0QeQsf5st6Jo0tL9Qd7YgH3xh60p/GP
YLeP3wIoCabSXcYqXnxbHk7r8LhStt5iL3iegxgNNTh293m/YNl6PpUCgYEAyUwy
rSghh/xG1+oF4zMJvlUeTXO4PYVfDKKZIF3C/GfOmYFG9k1+oOnpa/+Agq5a9OpI
O1/chn5976d9yKMJqKlUC29SuXwBkz/C/Bp30UVW77kbrLSEtHrwVGenuRjZv9VF
NcHST+Jugns48SPE7uwYvZeBLuvq6Bs3wydByx8CgYEAmvFGsXrW4smdhdeE74aU
8XNymNGMK445WDZJAysyabgIoUTBpEVyX65pFyUoIdls3Yo226xg0Hm2xhhydbRE
Ymn+/ErbatiKLaHxZAATlvm5hrWQSXm1WXsznNd6UtKpwjGGjFRDJwAZ0+PpB+Wf
PouAWnrF93tiuPqbbjte8n0CgYEAr4vM8eb6fv3JxkfnRIDg8WSHnaHaPYSPJJS0
F17NSZM5v/LWsLtaP/hdwPo71zs4RTf/MBBkX8H2D8awUgWkybqJecNmkC2Nrh0/
7N0kOpNOwpZahR2UUVSZO/J9eVUrqDjUN5JE17evCglt2hWIi5fH56c1WHcTD8GU
upMEtJ8CgYBYf3EYou8etgJu3Bm6o2/ckg+dIbxUNF8X8JEWK9lrU/MznWuATZW2
kREdA/+kMwWp8McjVfQ98Vs4IiG22JXW8n0fczfcR7kld5n768jH8eHpUeid5o1+
mIHWHoiEYJvlV5mdLNY7ZaY4F4JFSbP4Bnc9V70r0nVND9lEwZfEIg==
-----END RSA PRIVATE KEY-----
EOH

    for i in `seq 1 $num_workers`; do
        workername="docker-slave-$i"
        docker build -t $workername \
            --build-arg BUILDMASTER="corenic-build.netronome.com" \
            --build-arg BUILDMASTER_PORT="9989" \
            --build-arg WORKERNAME="$workername" \
            --build-arg WORKERPASS="qwe123" \
            --build-arg SDK_DPKG_LOCATION="http://pahome.netronome.com/releases-intern/nfp-sdk/linux-x86_64/nfp-toolchain-6/dpkg/amd64/nfp-sdk_6.x-devel-3537-2_amd64.deb" \
            --build-arg SSH_KEY="$(cat /tmp/docker_key)" \
            -f Dockerfile.ubuntu1604 .
    done
    rm -f /tmp/docker_key

    echo
    echo "** Generated $num_workers docker worker images."
}

test_docker_workers() {
    cat <<EOH > /tmp/docker_test.py
#!/usr/bin/python
import docker
client = docker.client.Client(base_url="tcp://127.0.0.1:2375")
for i in range(1, ($num_workers+1)):
    worker_image = "docker-slave-%i" % i
    print "Testing worker: %s" % worker_image
    container = client.create_container(worker_image)
    client.start(container['Id'])
    client.stop(container['Id'])
    client.wait(container['Id'])
EOH
    chmod +x /tmp/docker_test.py
    /tmp/docker_test.py
    ret=$?
    echo
    if [ "$ret" -eq "0" ]; then
        echo "** Successfully tested docker workers."
    else
        echo "** FAILED to test docker workers!"
    fi
}

create_jobdir() {
    mkdir -p ./$jobdir ./$jobdir/new ./$jobdir/cur ./$jobdir/tmp
    chmod g+rwx,o-rwx ./$jobdir ./$jobdir/*

    echo
    echo "** Generated $jobdir job directory."
}

create_all() {
    if [ -e "master.cfg" ]; then
        cp master.cfg master.cfg.ctrl_bck
    fi
    create_buildbot_master
    mv master.cfg.ctrl_bck master.cfg
    create_service

    jobdir="jobs_nfp-drv-kmods"
    create_jobdir
    jobdir="jobs_sprite"
    create_jobdir
    jobdir="jobs_corenic"
    create_jobdir
    jobdir="jobs_abm"
    create_jobdir
    jobdir="jobs_bpf"
    create_jobdir

    create_docker_workers
    test_docker_workers

    service buildbot_${master_name} restart

    echo
    echo "** All done!"
    echo "   Enjoy your buildbot_${master_name} instance with base directory $(pwd)"
}

case $command in
    "all") create_all;;
    "docker") create_docker_workers;;
    "job") create_jobdir;;
    "master") create_buildbot_master;;
    "service") create_service;;
    "test_docker") test_docker_workers;;
    *)
        echo "Command not specified!"
        echo
        usage
        ;;
esac
