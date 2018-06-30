#!/bin/bash

BRANCH="`git rev-parse --abbrev-ref HEAD`"
HASH="`git rev-parse --short HEAD`"
TAG="`git describe --tags --exact-match 2> /dev/null`"
CHANGES=""

if [ ! -z "`git diff --name-only`" ] ; then
  CHANGES="+"
elif [ ! -z "`git diff --staged --name-only`" ]; then
  CHANGES="+"
fi

if [ -z "${TAG}" ] ; then
  NAME="`git describe --tags HEAD 2> /dev/null | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\1/'`"
  if [ -z ${NAME} -o \( ${BRANCH} != "master" -a ${NAME} = "nic" \) ] ; then
    NAME=${BRANCH}
  fi
  VERSION="`git describe --tags HEAD | sed 's/^[a-z|A-Z|-|_]*-\(.*\)-g[[:alnum:]]*$/\1/' | sed 's/%/~/g' | sed 's/-/\./g'`"
else
  NAME=`echo $TAG | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\1/'`
  VERSION=`echo $TAG | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\2/' | sed 's/%/~/g' | sed 's/-/\./g'`
fi

if [ "$1" = "--fw_id" ] ; then
  if [ -z "${TAG}" ] ; then
    TRUNC_NAME=`echo ${NAME} | sed 's/^wip[-|_]/@/' | cut -c1-6`
    TRUNC_HASH=`echo ${HASH} | cut -c1-6`
    echo ${TRUNC_NAME}-${TRUNC_HASH}${CHANGES}
  else
    echo ${TAG}${CHANGES} | sed 's/%/~/g'
  fi
elif [ "$1" = "--pkg_ver" ] ; then
  if [ -z "${TAG}" ] ; then
    echo ${VERSION}.${HASH}${CHANGES}
  else
    echo ${VERSION}${CHANGES}
  fi
elif [ "$1" = "--pkg_name" ] ; then
  echo ${NAME}
elif [ "$1" = "--nfld_args" ] ; then
  NFLD_VER=`echo ${VERSION} | sed 's/\([[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\).*/\1/'`
  NFLD_BUILD=`echo ${VERSION} | sed 's/[[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*.//'`
  NFLD_ARGS=""
  if [ -z ${CHANGES} ] ; then
    if [ ! -z "${NAME}" ] ; then
      NFLD_ARGS="${NFLD_ARGS} -fw_name ${NAME}"
    fi
    if [ ! -z "${NFLD_VER}" ] ; then
      NFLD_ARGS="${NFLD_ARGS} -fw_version ${NFLD_VER}"
    fi
    if [ ! -z "${NFLD_BUILD}" ] ; then
      NFLD_ARGS="${NFLD_ARGS} -fw_buildnum ${NFLD_BUILD}"
    fi
  fi
  echo ${NFLD_ARGS}
else
  echo ${NAME}-${VERSION}-${HASH}${CHANGES}
fi
