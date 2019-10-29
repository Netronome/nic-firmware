#!/bin/bash

# Copyright (c) 2017 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

BRANCH="`git rev-parse --abbrev-ref HEAD`"
HASH="`git rev-parse --short HEAD`"
TAG="`git describe --tags --exact-match 2> /dev/null`"
CHANGES=""

if [ -n "`git diff --name-only`" ] ; then
  CHANGES="+"
elif [ -n "`git diff --staged --name-only`" ]; then
  CHANGES="+"
fi

# Add a check to see if PATCHSET ENV is set, use this in version if found

if [ -n "$PATCHSET" ] ; then
    HASH="ps"$PATCHSET
fi

if [ -z "${TAG}" ] ; then
  LABEL="`git describe --tags HEAD 2> /dev/null | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\1/'`"
  if [ -z ${LABEL} -o \( ${BRANCH} != "master" -a ${LABEL} = "nic" \) ] ; then
    LABEL=${BRANCH}
  else
    LABEL=""
  fi
  VERSION="`git describe --tags HEAD | sed 's/^[a-z|A-Z|-|_]*-\(.*\)-g[[:alnum:]]*$/\1/' | sed 's/%/~/g' | sed 's/-/\./g'`"
else
  LABEL=`echo $TAG | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\1/'`
  if [ ${LABEL} = "nic" ] ; then
    LABEL=""
  fi
  VERSION=`echo $TAG | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\2/' | sed 's/%/~/g' | sed 's/-/\./g'`
fi

if [ "$1" = "--fw_id" ] ; then
  FW_ID="$2-"
  if [ -n "${LABEL}" ] ; then
    FW_ID="${FW_ID}`echo ${LABEL} | sed 's/^wip[-|_]/@/' | cut -c1-3`-"
  fi
  if [ -z "${TAG}" -o -n "${CHANGES}" ] ; then
    FW_ID="${FW_ID}`echo ${HASH} | cut -c1-5`${CHANGES}"
  else
    FW_ID="${FW_ID}`echo ${VERSION} | sed 's/%/~/g'`"
  fi
  echo ${FW_ID}
elif [ "$1" = "--deb_dir" ] ; then
  PKG_NAME="pkg/deb/agilio-${2}-firmware"
  if [ -n "${LABEL}" ] ; then
    PKG_NAME="${PKG_NAME}-${LABEL}"
  fi
  PKG_NAME="${PKG_NAME}-${VERSION}"
  if [ -z "${TAG}" -o -n "${CHANGES}" ] ; then
    PKG_NAME="${PKG_NAME}.${HASH}${CHANGES}"
  fi
  echo "${PKG_NAME}-1"
elif [ "$1" = "--pkg_name" ] ; then
  PKG_NAME="agilio-${2}-firmware"
  if [ -n "${LABEL}" ] ; then
    PKG_NAME="${PKG_NAME}-${LABEL}"
  fi
  echo ${PKG_NAME}
elif [ "$1" = "--pkg_ver" ] ; then
  PKG_VER="${VERSION}"
  if [ -z "${TAG}" -o -n "${CHANGES}" ] ; then
    PKG_VER="${PKG_VER}.${HASH}${CHANGES}"
  fi
  echo ${PKG_VER}
elif [ "$1" = "--nfld_args" ] ; then
  NFLD_VER=`echo ${VERSION} | sed 's/\([[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\).*/\1/'`
  NFLD_BUILD=`echo ${VERSION} | sed 's/[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*.//'`
  NFLD_ARGS="-fw_typeid $2"
  if [ -n "${LABEL}" ] ; then
    NFLD_ARGS="${NFLD_ARGS}-${LABEL}"
  fi
  if [ -z "${CHANGES}" ] ; then
    if [ -n "${NFLD_VER}" ] ; then
      NFLD_ARGS="${NFLD_ARGS} -fw_version ${NFLD_VER}"
    fi
    if [ -n "${NFLD_BUILD}" ] ; then
      NFLD_ARGS="${NFLD_ARGS} -fw_buildnum ${NFLD_BUILD}"
    fi
  fi
  echo ${NFLD_ARGS}
else
  if [ -n "${LABEL}" ] ; then
    echo -n ${LABEL}-
  fi
  echo ${VERSION}-${HASH}${CHANGES}
fi
