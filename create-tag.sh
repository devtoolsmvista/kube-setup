#!/bin/bash

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TOPDIR=/tmp/koji-setup

if [ -z "$GIT_HOST_IP" ] ; then
    #GIT_HOST_IP="$(hostname -i)"
    GIT_HOST_IP="10.40.0.50"
    export GIT_HOST_IP=${GIT_HOST_IP}
fi
if [ -z "$MIRROR_HOST_IP" ] ; then
    #MIRROR_HOST_IP="$(hostname -i)"
    MIRROR_HOST_IP="10.40.5.50"
    export MIRROR_HOST_IP=${MIRROR_HOST_IP}
fi
if [ -z "$COLLECTIVE_HOST_IP" ] ; then
    #COLLECTIVE_HOST_IP="$(hostname -i)"
    COLLECTIVE_HOST_IP="10.40.4.102"
    export COLLECTIVE_HOST_IP=${COLLECTIVE_HOST_IP}
fi
while getopts 'c:' OPTION; do
    case "$OPTION" in
      c)
        CENTOS_MINOR_RELEASE=$OPTARG
        echo "Setting CENTOS_MINOR_RELEASE=$CENTOS_MINOR_RELEASE"
        ;;
      ?)
        echo "usage: $(basename $0) [-c <5|6|7>]" >& 2
        echo "use -c option to set CENTOS_MINOR_RELEASE" >& 2
        exit 1
        ;;
    esac

done
shift $((OPTIND-1))



bootstrap_build_in_koji_client_container() {
  source $TOPDIR/koji-jenkins-setup/run-scripts/parameters.sh

  KOJI_HUB_HOST_IP="$(kubectl get pods -o wide |grep koji-hub | awk '{print $6}')"
  echo "KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP}"
  echo "CENTOS_MINOR_RELEASE=${CENTOS_MINOR_RELEASE}"

  CENTOS_MINOR_RELEASE=${CENTOS_MINOR_RELEASE} TOPDIR=${TOPDIR} KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst < ${SCRIPT_DIR}/10-kojiclient-deployment.tmpl > ${SCRIPT_DIR}/10-kojiclient-deployment.yaml

  kubectl apply -f ${SCRIPT_DIR}/10-kojiclient-deployment.yaml
  sleep 30
  KOJI_CLIENT_POD_NAME="$(kubectl get pods -o wide |grep koji-client  | awk '{print $1}')"
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- koji moshimoshi
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- env | grep CENTOS_MINOR_RELEASE
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- bash /root/run-scripts/bootstrap-build.sh

  sleep 5

  kubectl delete deployment koji-client
  # restart jenkins master so it will create jobs for the new tag
  kubectl rollout restart deployment/koji-jenkins
  
}


bootstrap_build_in_koji_client_container
