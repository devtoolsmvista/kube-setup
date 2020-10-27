#!/bin/bash

#set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TOPDIR=/tmp/koji-setup


KOJI_HUB_HOST_IP="$(kubectl get pods -o wide |grep koji-hub | awk '{print $6}')"
echo "KOJI_HUB_HOST_IP=${KOJI_HUB_HOST_IP}"

function create_tag(){
  # default values
  CENTOS_SUFFIX=""
  CENTOS_MINOR_RELEASE="6"
  CENTOS_MAJOR_RELEASE="7"
  CONF=""
  # values from function parameters
  if [ $# -ge 1 ]; then
    CENTOS_SUFFIX=$1
  fi 
  if [ $# -ge 2 ]; then
    CENTOS_MINOR_RELEASE=$2
  fi 
  if [ $# -ge 3 ]; then
    CENTOS_MAJOR_RELEASE=$3
  fi 
  if [ $# -ge 4 ]; then
    CONF=$4
  fi 
  source $TOPDIR/koji-jenkins-setup/run-scripts/parameters.sh

  KOJI_JENKINS_HOST_IP="$(kubectl get pods -o wide |grep koji-jenkins | awk '{print $6}')"
  echo "KOJI_JENKINS_HOST_IP=${KOJI_JENKINS_HOST_IP}"

  HOST=${KOJI_JENKINS_HOST_IP} $TOPDIR/koji-jenkins-setup/run-scripts/checkinitStart.sh
  HOST=${KOJI_JENKINS_HOST_IP} $TOPDIR/koji-jenkins-setup/run-scripts/checkforinitalcheckout.sh
  while true; do
    read -p "Are you ready to create (${CENTOS_MAJOR_RELEASE}:${CENTOS_MINOR_RELEASE}:${CENTOS_SUFFIX}) tags? Make sure no failed job creations. [N/y]" yn
    case $yn in
      [Yy]* )
        break;;
      * )
        echo "Not ready yet. Waiting for another minute..."
        sleep 60
        break;;
    esac
  done

  if [ -z $PREV_APP_BUILD_BRANCHES ]; then
    #get current DISTRO_APP_BRANCH environment variable from koji-jenkins pod
    KOJI_JENKINS_POD_NAME="$(kubectl get pods -o wide |grep koji-jenkins  | awk '{print $1}')"
    PREV_APP_BUILD_BRANCHES=$(kubectl exec -it ${KOJI_JENKINS_POD_NAME} -- env | grep DISTRO_APP_BRANCH)
    PREV_APP_BUILD_BRANCHES=$(echo $PREV_APP_BUILD_BRANCHES | dos2unix)
    PREV_APP_BUILD_BRANCHES=${PREV_APP_BUILD_BRANCHES#"DISTRO_APP_BRANCH="}
    echo "PREV_APP_BUILD_BRANCHES=${PREV_APP_BUILD_BRANCHES}"
    sleep 10
  fi
  if [ "$APP_BUILD_BRANCHES" != "$PREV_APP_BUILD_BRANCHES" ]; then
    echo "update environment variable DISTRO_APP_BRANCH=${APP_BUILD_BRANCHES} in koji-jenkins"
    kubectl set env deployment koji-jenkins DISTRO_APP_BRANCH="${APP_BUILD_BRANCHES}"
    sleep 60
  fi
  PREV_APP_BUILD_BRANCHES=$APP_BUILD_BRANCHES

  ${SCRIPT_DIR}/create-tag.sh -m "${CENTOS_MAJOR_RELEASE}" -i "${CENTOS_MINOR_RELEASE}" -s "${CENTOS_SUFFIX}" -c "${CONF}"
  sleep 60
}

function create_all_tags(){
 
  #Nokia
  while true; do 
    read -p "Do you wish to create tags for Nokia? [N/y]" yn
    case $yn in 
      [Yy]* ) 
        echo "Creating tags for Nokia...";
        create_tag "" "5" 
        create_tag "" "6" 
        create_tag "" "7" 
        create_tag "" "" 
        create_tag "" "8" 
        break;;
      * )
        echo "No selected, will not proceed with tag creation for Nokia";
        break;;
    esac
  done
  #Streams
  while true; do
    read -p "Do you wish to create tags for Stream? [N/y]" yn
    case $yn in
      [Yy]* )
        echo "Creating tags for Stream";
        create_tag "" "s" "8" "centos-updates-mv-s"
        break;;
      * )
        echo "No selected, will not proceed with tag creation for Stream";
        break;;
    esac
   done

  #Ericsson
  while true; do 
    read -p "Do you wish to create tags for Ericsson? [N/y]" yn
    case $yn in 
      [Yy]* ) 
        echo "Creating tags for Ericcson...";
        create_tag "-e" "7" 
        create_tag "-e" "8" 
        break;;
      * )
        echo "No selected, will not proceed with tag creation for Ericcson";
        break;;
    esac
  done

  #Samsung
  while true; do 
    read -p "Do you wish to create tags for Samsung? [N/y]" yn
    case $yn in 
      [Yy]* ) 
        echo "Creating tags for Samsung...";
        create_tag "-sam" "6" 
        create_tag "-sam" "7" 
        create_tag "-sam" "8" 
        create_tag "-sam" "1" "8" 
        break;;
      * )
        echo "No selected, will not proceed with tag creation for Samsung";
        break;;
    esac
  done


}

create_all_tags

