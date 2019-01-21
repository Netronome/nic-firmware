#!/bin/bash

FILTER=$1
shift
TEST_DIR=$1
shift
TEST_BUILD_DIR=$1
mkdir -p ${TEST_BUILD_DIR}
shift
FW_BUILD_DIR=$1
shift
if [ -z ${Q+x} ];
then
    set +x
else
    set -x
fi
PASSED=0
FAILED=0

COLOR_PASS=${COLOR_PASS:-"\033[1;32m"}
COLOR_FAIL=${COLOR_FAIL:-"\033[1;31m"}
COLOR_WARN=${COLOR_WARN:-"\033[1;33m"}
COLOR_RESET=${COLOR_RESET:-"\e[0m"}

for t in `find ${TEST_DIR} -iname '*_test.uc' -o -iname '*_test.c'` ; do
    if echo ${t} | grep -v ${FILTER} > /dev/null ; then
        continue
    fi
    FILE_BASE=`basename ${t%.*}`
    if echo ${t} | grep '.uc' > /dev/null ; then
        nfas -Itest/include -Itest/lib $* -o ${TEST_BUILD_DIR}/${FILE_BASE}.list $t || exit 1
        nfld -chip nfp-4xxx-b0 -mip -rtsyms -map -u i32.me0 ${TEST_BUILD_DIR}/${FILE_BASE}.list || exit 1
    else
        of=" "
        for obj in `find ${FW_BUILD_DIR} -iname '*.obj'` ; do
            of=$of" "$obj
        done
        nfcc -chip nfp-4xxx-b0 -v1 -Itest/include -Itest/lib $* -o ${TEST_BUILD_DIR}/${FILE_BASE}.list $t ${of} || exit 1
        nfld -chip nfp-4xxx-b0 -mip -rtsyms -map -u i32.me0 ${TEST_BUILD_DIR}/${FILE_BASE}.list || exit 1
    fi

    nfp-nffw unload || exit 1
    nfp-nffw load -S ${TEST_BUILD_DIR}/${FILE_BASE}.nffw || exit 1
    awk '$0~/;TEST_INIT_EXEC/{system(gensub(";TEST_INIT_EXEC ", "", 1))}' < ${TEST_BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw start
    TIMEOUT=10
    echo -n "${FILE_BASE} : "
    while [[ `nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2` -eq "0" ]] ; do
       sleep 1
       echo -n ". "
       TIMEOUT=$((TIMEOUT - 1))
       [[ ${TIMEOUT} -eq 0 ]] && break
    done
    RESULT=`nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2`
    if [[ ${RESULT} -eq "1" ]] ; then
        echo -e "${COLOR_PASS}PASS${COLOR_RESET}"
        PASSED=$(( ${PASSED} + 1 ))
    else
        TESTED=`nfp-reg mecsr:i32.me0.Mailbox2 | cut -d= -f2`
        EXPECTED=`nfp-reg mecsr:i32.me0.Mailbox3 | cut -d= -f2`
        if [[ ${RESULT} -eq "0xfa" ]] ; then
            DETAIL="- assertion failed"
        elif [[ ${RESULT} -eq "0xfc" ]] ; then
            DETAIL=`printf -- "- expected 0x%08x, got 0x%08x" ${EXPECTED} ${TESTED}`
        elif [[ ${RESULT} -eq "0xfe" ]] ; then
            DETAIL=`printf -- "- unexpectedly got 0x%08x" ${TESTED}`
        fi
        STS=`nfp-reg mecsr:i32.me0.mailbox_1 | cut -d= -f2`
        PC=$(( (STS >> 8) & 0x1ffff ))
        ISL=$(( (STS >> 25) & 0x3f ))
        ME=$(( ((STS >> 3) & 0xf) - 4 ))
        CTX=$(( STS & 0x7 ))
        echo -en "${COLOR_FAIL}FAIL${COLOR_RESET}"
        if [[ ${RESULT} -eq 0 ]] ; then
            echo "(timed out)"
        else
            echo "@ i${ISL}.me${ME}.ctx${CTX}:${PC} ${DETAIL}"
        fi
        FAILED=$(( ${FAILED} + 1 ))
    fi
done
if [[ ${FAILED} -eq 0 ]] && [[ ${PASSED} -ge 1 ]] ; then
    echo -e "Summary : ${COLOR_PASS}${PASSED} passed, no failures${COLOR_RESET}"
    exit 0
else
    echo -e "Summary : ${COLOR_WARN}${PASSED} passed, ${FAILED} failed${COLOR_RESET}"
    exit 1
fi
