#!/bin/bash

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TOPDIR=/tmp/koji-setup

if [ -z "$GIT_HOST_IP" ] ; then
    GIT_HOST_IP="$(hostname -i)"
    export GIT_HOST_IP="$(hostname -i)"
fi
if [ -z "$MIRROR_HOST_IP" ] ; then
    MIRROR_HOST_IP="$(hostname -i)"
    export MIRROR_HOST_IP="$(hostname -i)"
fi

if ! ping $GIT_HOST_IP -c 1 >/dev/null 2>/dev/null; then
    echo "$GIT_HOST_IP does not appear to be reachable from this machine."
    echo "if ping does not work, it won't work in the container and will fail to start"
    exit 1
fi
if ! ping $MIRROR_HOST_IP -c 1 >/dev/null 2>/dev/null; then
    echo "$MIRROR_HOST_IP does not appear to be reachable from this machine."
    echo "if ping does not work, it won't work in the container and will fail to start"
    exit 1
fi
if [ -z "$MASH_INGRESS_HOSTNAME" ] ; then
    MASH_INGRESS_HOSTNAME="$(hostname -s).mash"
    export MASH_INGRESS_HOSTNAME=${MASH_INGRESS_HOSTNAME}
fi


cd $TOPDIR
cd koji-jenkins-setup
source run-scripts/parameters.sh

# dynamically get koji host ip
KOJI_HUB_HOST_IP="$(kubectl get pods -o wide |grep koji-hub | awk '{print $6}')"

kubectl apply -f ${SCRIPT_DIR}/00-koji-mash-namespace.yaml
echo "${KOJI_HUB_HOST_IP}"
TOPDIR=${TOPDIR} KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst < ${SCRIPT_DIR}/01-mash-deployment.tmpl > ${SCRIPT_DIR}/01-mash-deployment.yaml
kubectl apply -f ${SCRIPT_DIR}/01-mash-deployment.yaml

#cat ${SCRIPT_DIR}/01-mash-deployment.tmpl | KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst | kubectl apply -f -
kubectl apply -f ${SCRIPT_DIR}/02-mash-service.yaml
#kubectl apply -f ${SCRIPT_DIR}/03-mash-ingress.yaml
cat ${SCRIPT_DIR}/03-mash-ingress.tmpl | MASH_INGRESS_HOSTNAME="${MASH_INGRESS_HOSTNAME}" envsubst | kubectl apply -f -


