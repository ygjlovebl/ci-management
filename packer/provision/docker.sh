#!/bin/bash

# vim: sw=4 ts=4 sts=4 et :

add_jenkins_user() {
    git clone https://gerrit.hyperledger.org/r/ci-management.git /ci-management
    /ci-management/jenkins-scripts/init_system.sh
}

rh_changes() {
    echo "---> RH changes"
    # install docker and enable it
    echo "---> Installing docker"
    yum install -y docker supervisor bridge-utils
    systemctl enable docker

    # configure docker networking so that it does not conflict with LF
    # internal networks
    cat <<EOL > /etc/sysconfig/docker-network
# /etc/sysconfig/docker-network
DOCKER_NETWORK_OPTIONS='--bip=10.250.0.254/24'
EOL
    # configure docker daemon to listen on port 5555 enabling remote
    # managment
    sed -i -e "s#='--selinux-enabled'#='--selinux-enabled --mtu 1392 -H unix:///var/run/docker.sock -H tcp://0.0.0.0:5555'#g" /etc/sysconfig/docker

    # docker group doesn't get created by default for some reason
    groupadd docker

    # Install python dependencies
    yum install -y python-{devel,virtualenv,setuptools,pip}
}

deb_docker_fix(){
    echo "---> Fixing docker"
    systemctl stop docker
    cat <<EOL > /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target docker.socket
Requires=docker.socket

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=
ExecStart=/usr/bin/dockerd --mtu 1392 -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
EOL
    systemctl start docker
    echo "---> Check the MTU here"
    docker network inspect bridge
    echo "---> MTU should be 1392"
}

deb_install_go() {
    echo "---> Installing Go"

    curl -sL -o /usr/local/bin/gimme https://raw.githubusercontent.com/travis-ci/gimme/master/gimme
    chmod +x /usr/local/bin/gimme

    gimme 1.7 /opt/go
}

deb_docker_pull_baseimage() {
    echo "---> Pulling Fabric Baseimage"
    docker pull hyperledger/fabric-baseimage:x86_64-0.0.10
}

deb_create_hyperledger_vardir() {
    echo "---> Creating Hyperledger Vardir"
    mkdir /var/hyperledger/
    chown $USER:$USER /var/hyperledger
}

deb_install_rocksdb() {
    #cd scripts/provision/ && chmod +x host.sh && sudo ./host.sh
    echo "---> Installing RocksDB"

    git clone --branch v4.1 \
        --single-branch \
        --depth 1 \
        https://github.com/facebook/rocksdb.git /tmp/rocksdb

    cd /tmp/rocksdb
    make shared_lib
    INSTALL_PATH='/usr/local' make install-shared
    ldconfig
}

deb_add_docker_repo() {
    echo '---> Installing the Docker Repo'
    apt-key adv \
      --keyserver hkp://p80.pool.sks-keyservers.net:80 \
      --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main"|tee /etc/apt/sources.list.d/docker.list
    apt-get update
}

deb_install_docker_compose() {
    echo '---> Installing Docker Compose'
    curl -sL "https://github.com/docker/compose/releases/download/1.8.1/docker-compose-`uname -s`-`uname -m`" > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    docker-compose --version
}

deb_install_pip_pkgs() {
    PIP_PACKAGE_DEPS="urllib3 pyopenssl ndg-httpsclient pyasn1 ecdsa python-slugify grpcio-tools"
    PIP_PACKAGES="behave nose"
    GRPC_PACKAGES="grpcio==1.0.4"
    JINJA2_PACKAGES="jinja2"
    B3J0F_PACKAGES="b3j0f.aop"
    PIP_VERSIONED_PACKAGES="flask==0.10.1 \
        python-dateutil==2.2 pytz==2014.3 pyyaml==3.10 couchdb==1.0 \
        flask-cors==2.0.1 requests==2.12.1 pysha3==1.0b1"

    echo '---> Installing Pip Packages'
    pip3 install -U pip
    pip3 install $PIP_PACKAGE_DEPS
    pip3 install $PIP_PACKAGES
    pip3 install -I $PIP_VERSIONED_PACKAGES
    pip3 install -U $GRPC_PACKAGES $JINJA2_PACKAGES $B3J0F_PACKAGES
}

deb_update_alternatives() {
    echo '---> Updating Alternatives'
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 90
}

deb_install_python() {
    # Python install
    echo python install
    PACKAGES="python3-venv python3-pip python2.7-dev python-virtualenv python-setuptools python-pip"
    apt-get -qq install -y $PACKAGES
}

deb_install_softhsm() {
    apt-get -qq install -y softhsm2

    # Create tokens directory
    mkdir -p /var/lib/softhsm/tokens/

    # Add jenkins user to softhsm group
    chown -r $USER:$USER /var/lib/softhsm /etc/softhsm

    #Initialize token
    softhsm2-util --init-token --slot 0 --label "ForFabric" --so-pin 1234 --pin 98765432
}

deb_install_node() {
    # Node install
    pushd /usr/local
    curl https://nodejs.org/dist/v7.4.0/node-v7.4.0-linux-x64.tar.xz | tar xJf - --strip-components=1
    popd
    echo npm -v: `npm -v`
    echo node -v: `node -v`
}

deb_install_pkgs() {
    # Compiling Essentials
    PACKAGES="g++-4.8 build-essential software-properties-common curl sudo zip libtool"

    # Libraries
    PACKAGES="$PACKAGES libsnappy-dev zlib1g-dev libbz2-dev \
        libffi-dev libssl-dev python-dev libyaml-dev python-pip"

    # Packages for IBM fvt
    PACKAGES="$PACKAGES haproxy haproxy-doc htop html2text isag jq \
        libdbd-pg-perl locales-all mysql-client mysql-common \
        mysql-server postgresql postgresql-contrib \
        postgresql-doc vim-haproxy zsh"

    # Tox for py-sdk
    PACKAGES="$PACKAGES tox"

    # maven for sdk-java
    PACKAGES="$PACKAGES maven"

    # Tcl prerequisites for busywork
    PACKAGES="$PACKAGES tcl tclx tcllib"

    # Docker
    PACKAGES="$PACKAGES apparmor \
        linux-image-extra-$(uname -r) docker-engine"

    echo '---> Installing packages'
    apt-get -qq install -y $PACKAGES
    docker --version
}

deb_add_apt_ppa() {
    echo '---> Adding Ubuntu PPAs'
    add-apt-repository -y $@
    apt-get -qq update
}

ubuntu_changes() {
    echo "---> Ubuntu changes"
    export DEBIAN_FRONTEND=noninteractive

    deb_install_go
    deb_create_hyperledger_vardir
    deb_add_docker_repo
    deb_add_apt_ppa 'ppa:ubuntu-toolchain-r/test'
    deb_install_pkgs
    deb_install_python
    deb_install_pip_pkgs
    add_jenkins_user
    deb_install_docker_compose
    deb_install_node
    deb_install_softhsm
    deb_install_rocksdb
    deb_update_alternatives
    deb_docker_pull_baseimage
    deb_docker_fix

    echo "---> No extra steps presently for ${FACTER_OS}"
}

OS=$(/usr/bin/facter operatingsystem)
case "$OS" in
    CentOS|Fedora|RedHat)
        rh_changes
    ;;
    Ubuntu)
        ubuntu_changes
    ;;
    *)
        echo "${OS} has no configuration changes"
    ;;
esac
