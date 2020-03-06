#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

source "$SCRIPT_DIR"/parameters.sh
TOPDIR=$(dirname $SCRIPT_DIR)
cd $TOPDIR

commonBuild=$(basename $COMMON_BUILD_REPO | sed s,.git,,)
echo $commonBuild
if [ ! -d $commonBuild ] ; then
   git clone -b $COMMON_BUILD_BRANCH $COMMON_BUILD_REPO
else
   pushd $commonBuild
       git checkout $COMMON_BUILD_BRANCH
       git pull
   popd
fi

koji -q list-hosts | while read HOST B; do koji edit-host $HOST --arches 'x86_64 i686' ; done 
EXTERNAL_REPO=$(cat $commonBuild/conf/centos-updates.cfg  | grep ^baseurl | cut -d = -f 2)

#$TOPDIR/run-scripts/fetch-previous.sh
sleep 5
SRC_RPM_DIR=/builds/srpms
BIN_RPM_DIR=/builds/rpms
ls /builds
sleep 5

if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	find "$SRC_RPM_DIR" -name '*.src.rpm' | xargs -n 1 -I {}  koji import {}
	find "$BIN_RPM_DIR" -name "*.rpm" | xargs -n 1 -I {}  koji import {}
	if [[ -n "$DEBUG_RPM_DIR" ]]; then
		find "$DEBUG_RPM_DIR" -name "*.rpm" | xargs -n 1 -I {}  koji import {}
	fi
fi
 koji add-tag dist-"$TAG_NAME"
 koji edit-tag dist-"$TAG_NAME" -x mock.package_manager=dnf
if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	 koji list-pkgs --quiet | xargs -I {}  koji add-pkg --owner kojiadmin dist-"$TAG_NAME" {}
	 koji list-untagged | xargs -n 1 -I {}  koji call tagBuildBypass dist-"$TAG_NAME" {}
fi
 koji add-tag --parent dist-"$TAG_NAME" --arches "$RPM_ARCH" dist-"$TAG_NAME"-build
 koji add-target dist-"$TAG_NAME" dist-"$TAG_NAME"-build
 koji add-group dist-"$TAG_NAME"-build build
 koji add-group dist-"$TAG_NAME"-build srpm-build
 koji add-group-pkg dist-"$TAG_NAME"-build build $RELEASE_PACKAGE autoconf automake binutils bzip2 coreutils diffutils gawk gcc gcc-c++ gettext git glibc-devel glibc-common glibc-utils grep gzip hostname libcap libtool kernel-headers m4 make setup patch pigz pkgconfig redhat-rpm-config rpm-build sed shadow-utils systemd-libs tar unzip which xz
# clr-rpm-config

 koji add-group-pkg dist-"$TAG_NAME"-build srpm-build $RELEASE_PACKAGE coreutils cpio curl git glibc-utils grep gzip make rpm-build redhat-rpm-config sed shadow-utils tar unzip wget xz
# plzip
if [[ -n "$EXTERNAL_REPO" ]]; then
	for REPO in $EXTERNAL_REPO; do
		REPO_NAME=$(echo $REPO | sed -e "s,https://,," -e "s,http://,," -e "s,/$,," -e "s,/,\-,g")
		 koji add-external-repo -t dist-"$TAG_NAME"-build dist-"$TAG_NAME"-external-repo-$REPO_NAME "$REPO"
	done
fi
 koji regen-repo dist-"$TAG_NAME"-build
