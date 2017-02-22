#!/bin/bash -exu
set -o pipefail

source ${WORKSPACE}/src/test/fabric_test_commitlevel.sh

# Clone fabric git repository
#############################

rm -rf ${WORKSPACE}/gopath/src/github.com/hyperledger/fabric

WD="${WORKSPACE}/gopath/src/github.com/hyperledger/fabric"
REPO_NAME=fabric
git clone https://github.com/hyperledger/$REPO_NAME.git $WD
cd $WD
git checkout $FABRIC_COMMIT
FABRIC_COMMIT_LEVEL=$(git log -1 --pretty=format:"%h")
make docker
docker images | grep hyperledger

# Clone fabric-ca git repository
################################

rm -rf ${WORKSPACE}/gopath/src/github.com/hyperledger/fabric-ca

WD="${WORKSPACE}/gopath/src/github.com/hyperledger/fabric-ca"
CA_REPO_NAME=fabric-ca
git clone https://github.com/hyperledger/$CA_REPO_NAME.git $WD
cd $WD
git checkout $FABRIC_CA_COMMIT
CA_COMMIT_LEVEL=$(git log -1 --pretty=format:"%h")
make docker
docker images | grep hyperledger

# Move to fabric-sdk-java repository and execute end-to-end tests

export WD=${WORKSPACE}
cd $WD
JAVA_SDK_COMMIT_LEVEL=$(git log -1 --pretty=format:"%h")
echo "=======>" "FABRIC COMMIT NUMBER" "-" $FABRIC_COMMIT_LEVEL "=======>" "FABRIC CA COMMIT NUMBER" "-" $CA_COMMIT_LEVEL "=======>" "FABRIC SDK JAVA COMMIT NUMBER" "-" $JAVA_SDK_COMMIT_LEVEL >> commit_history.log
export GOPATH=$WD/src/test/fixture
cd $WD/src/test/fixture/src
rm -rf /tmp/keyValStore*; rm -rf  /tmp/kvs-hfc-e2e ~/test.properties; rm -rf /var/hyperledger/*  ; docker-compose up > dockerlogfile.log 2>&1 & 
cd $WD
sleep 30
docker ps -a
mvn clean install -DskipITs=false -Dmaven.test.failure.ignore=false