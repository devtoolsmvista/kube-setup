#!/bin/bash

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TOPDIR=/tmp/koji-setup
KOJI_JENKINS_SETUP_REPO=git://gitcentos.mvista.com/centos/upstream/docker/koji-jenkins-setup.git


if [ -z "$HOST" ] ; then
    HOST="$(hostname -f)"
fi
if [ -z "$HOST_IP" ] ; then
    HOST_IP="$(hostname -i)"
    export HOST_IP="$(hostname -i)"
fi
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

if [ -z "$KOJIHUB_INGRESS_HOSTNAME" ] ; then
    KOJIHUB_INGRESS_HOSTNAME="$(hostname -s)"
    export KOJIHUB_INGRESS_HOSTNAME=${KOJIHUB_INGRESS_HOSTNAME}
fi
if [ -z "$JENKINS_INGRESS_HOSTNAME" ] ; then
    JENKINS_INGRESS_HOSTNAME="jenkins.localhost"
    export JENKINS_INGRESS_HOSTNAME=${JENKINS_INGRESS_HOSTNAME}
fi

if ! ping $HOST -c 1 >/dev/null 2>/dev/null; then
    echo "$HOST does not appear to be reachable from this machine."
    echo "if ping does not work, it won't work in the container and will fail to start"
    exit 1
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
if ! ping $COLLECTIVE_HOST_IP -c 1 >/dev/null 2>/dev/null; then
    echo "$COLLECTIVE_HOST_IP does not appear to be reachable from this machine."
    echo "if ping does not work, it won't work in the container and will fail to start"
    exit 1
fi


while getopts 'ri' OPTION; do
    case "$OPTION" in
      r)
        echo "skip installation and configuration, only restart containers"
        do_installation="false"
        ;;
      i)
        echo "installation and configuration option is set"
        do_installation="true"
        ;;
      ?)
        echo "usage: $(basename $0) [-c]" >& 2
        echo "use -c option to clean existing setup" >& 2
        exit 1
        ;;
    esac

done
shift $((OPTIND-1))
# if no option specified, perform installation and configuration as default
if (( $OPTIND == 1)); then
    echo "perform installation and configuration when no option is specified"
    do_installation="true"
fi

prepare_working_directory () {
    if [ -d "$TOPDIR" ]; then
      sudo rm -rf "$TOPDIR"/*
    else
      mkdir -p $TOPDIR
    fi
    if [ -d /db/postgres/data ]; then
      sudo chmod 777 -R /db/postgres/data
      sudo rm -rf /db/postgres/data/*
    else 
      mkdir -p /db/postgres/data
      sudo chmod 777 /db/postgres/data
    fi
    if [ -d /koji/saved/etc/pki/koji ]; then
      sudo chmod 777 -R /koji/saved/etc/pki/koji
      sudo rm -rf /koji/saved/etc/pki/koji/*
    else
      mkdir -p /koji/saved/etc/pki/koji
    fi
    cd $TOPDIR
    git clone $KOJI_JENKINS_SETUP_REPO
    cd koji-jenkins-setup
    source run-scripts/parameters.sh
    sudo rm -rf $KOJI_CONFIG/*
    sudo rm -rf $KOJI_OUTPUT/*
}

prepare_koji_hub_container_setup () {
    mkdir -p $KOJI_OUTPUT $KOJI_CONFIG
    # Provide inital apps.list
    if [ -d "$KOJI_CONFIG"/koji ]; then
      sudo rm -rf "$KOJI_CONFIG"/koji/*
    else
      mkdir -p $KOJI_CONFIG/koji/
    fi
    cp $TOPDIR/koji-jenkins-setup/configs/app.list $KOJI_CONFIG/koji/
}


prepare_jenkins_container_setup () {
    if [ -d "$JENKINS_HOME" ]; then
      sudo rm -rf "$JENKINS_HOME"/*
    else
      mkdir -p $JENKINS_HOME
    fi
}

startup_koji_hub () {
  sudo rm -rf $KOJI_CONFIG/.done
  if [ "$do_installation" == "false" ]; then
    export DO_INSTALLATION=false
  else
    export DO_INSTALLATION=true
  fi


  #kubectl delete deployment koji
  kubectl apply -f ${SCRIPT_DIR}/00-postgres-configmap.yaml
  kubectl apply -f ${SCRIPT_DIR}/01-postgres-storage.yaml
  cat ${SCRIPT_DIR}/02-kojihub-configmap.tmpl | envsubst | kubectl apply -f -
  kubectl apply -f ${SCRIPT_DIR}/03-kojihub-storage.yaml
  cat ${SCRIPT_DIR}/04-koji-deployment.tmpl | envsubst | kubectl apply -f -
  #kubectl apply -f ${SCRIPT_DIR}/04-koji-deployment.yaml
  kubectl apply -f ${SCRIPT_DIR}/05-postgres-service.yaml
  kubectl apply -f ${SCRIPT_DIR}/06-kojihub-service.yaml

  while [ ! -e $KOJI_CONFIG/.done -a ! -e $KOJI_CONFIG/.failed ] ; do
	echo -n "."
	sleep 10 
  done

  # setup koji-hub ingress controller
  cat ${SCRIPT_DIR}/07-kojihub-ingress.tmpl | KOJIHUB_INGRESS_HOSTNAME="${KOJIHUB_INGRESS_HOSTNAME}" envsubst | kubectl apply -f -
  # dynamically get koji host ip
  KOJI_HUB_HOST_IP="$(kubectl get pods -o wide |grep koji-hub | awk '{print $6}')"

  if [ -e $KOJI_CONFIG/.failed -a ! $KOJI_CONFIG/.done ] ; then
   echo "ERROR: Koji Hub start failed."
   exit 1
  fi
}
bootstrap_build_in_koji_client_container() {
  mkdir -p $TOPDIR/koji-jenkins-setup/run-scripts2
  cp $TOPDIR/koji-jenkins-setup/run-scripts/* $TOPDIR/koji-jenkins-setup/run-scripts2
  sed -i $TOPDIR/koji-jenkins-setup/run-scripts2/bootstrap-build.sh -e 's,$TOPDIR/run-scripts/fetch-previous.sh, ,'

  echo "${KOJI_HUB_HOST_IP}"

  CENTOS_MINOR_RELEASE=${CENTOS_MINOR_RELEASE} TOPDIR=${TOPDIR} KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst < ${SCRIPT_DIR}/10-kojiclient-deployment.tmpl > ${SCRIPT_DIR}/10-kojiclient-deployment.yaml
  kubectl apply -f ${SCRIPT_DIR}/10-kojiclient-deployment.yaml
  sleep 30
  KOJI_CLIENT_POD_NAME="$(kubectl get pods -o wide |grep koji-client  | awk '{print $1}')"
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- koji moshimoshi
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- bash /root/run-scripts/bootstrap-build.sh
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- bash /root/run-scripts/package-add.sh
  kubectl exec -it ${KOJI_CLIENT_POD_NAME} -- koji grant-permission repo user

  sleep 5

  kubectl delete deployment koji-client
   
  
}
startup_koji_builder () {
  if [ ! -d "$KOJI_MOCK" ]; then
    mkdir -p $KOJI_MOCK
  fi
  echo "${KOJI_HUB_HOST_IP}"
  KOJI_MOCK=${KOJI_MOCK} KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst < ${SCRIPT_DIR}/09-kojibuilder-deployment.tmpl > ${SCRIPT_DIR}/09-kojibuilder-deployment.yaml
  kubectl apply -f ${SCRIPT_DIR}/09-kojibuilder-deployment.yaml
  sleep 30
}
prepare_jenkins() {
  echo $JENKINS_HOME
  USERDIR=$KOJI_CONFIG/user
  if [ ! -d $KOJI_CONFIG/user ] ; then
    USERDIR=$KOJI_CONFIG/users/user
  fi
  sudo mkdir -p $JENKINS_HOME/.koji/
  sudo cp -a $USERDIR/* $JENKINS_HOME/.koji/
  cat > $TOPDIR/config <<- EOF
[koji]
server = http://${KOJI_HUB_HOST_IP}/kojihub
weburl = http://${KOJI_HUB_HOST_IP}/koji
topurl = http://${KOJI_HUB_HOST_IP}/kojifiles
cert = ~/.koji/client.crt
ca = ~/.koji/clientca.crt
serverca = ~/.koji/serverca.crt
authtype = ssl
anon_retry = true
EOF
  sudo mv -f $TOPDIR/config $JENKINS_HOME/.koji/
  cp -a $TOPDIR/koji-jenkins-setup/jenkins/plugins.txt $TOPDIR/koji-jenkins-setup/jenkins/init/* $JENKINS_HOME
  sudo chown $JENKINS_UID.$JENKINS_UID -R $JENKINS_HOME
  env | grep BRANCH
}
startup_jenkins_container () {

  echo "${KOJI_HUB_HOST_IP}"
  KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP} envsubst < ${SCRIPT_DIR}/11-jenkins-deployment.tmpl > ${SCRIPT_DIR}/11-jenkins-deployment.yaml
  kubectl apply -f ${SCRIPT_DIR}/11-jenkins-deployment.yaml
  sleep 10
  kubectl apply -f ${SCRIPT_DIR}/12-jenkins-service.yaml
  #kubectl apply -f ${SCRIPT_DIR}/13-nginx-jenkins-ingress.yaml
  cat ${SCRIPT_DIR}/13-nginx-jenkins-ingress.tmpl | JENKINS_INGRESS_HOSTNAME="${JENKINS_INGRESS_HOSTNAME}" envsubst | kubectl apply -f -

}


if [ "$do_installation" == "true" ]; then
  echo "Performing installation and configuration..."
  sleep 3

  prepare_working_directory
  prepare_koji_hub_container_setup
  prepare_jenkins_container_setup
  startup_koji_hub
  startup_koji_builder
  bootstrap_build_in_koji_client_container
  prepare_jenkins
  startup_jenkins_container
else
  echo "Restart without configuration..."
  sleep 3
  cd $TOPDIR/koji-jenkins-setup
  source run-scripts/parameters.sh
  startup_koji_hub
  startup_koji_builder
  startup_jenkins_container
fi
