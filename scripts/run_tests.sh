#!/bin/bash

# Copyright (c) 2017-2020 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

FILTER=$1
shift
TEST_DIR=$1
shift
TEST_BUILD_DIR=$1
mkdir -p ${TEST_BUILD_DIR}
shift
FW_BUILD_DIR=$1
shift
NETRONOME=$1
shift
BLM_DIR=$1
shift

if [ -z ${Q+x} ];
then
    set +x
else
    set -x
fi

PASSED=0
FAILED=0
SKIPPED=0

BLM_LINK=

build_blm () {
    BLM_LINK="-u i48.me0 ${TEST_BUILD_DIR}/blm0.list"

    nfas -DNS_PLATFORM_TYPE=1 -third_party_addressing_40_bit -permit_dram_unaligned \
    -preproc64 -indirect_ref_format_nfp6000 -W3 -C -R -lr -go -g -lm 0 \
    -include ${TEST_BUILD_DIR}/../../apps/nic/config.h -chip nfp-4xxx-b0 \
    -DGRO_NUM_BLOCKS=1 -DBLM_CUSTOM_CONFIG -DBLM_INSTANCE_ID=0 -DNBII=8 \
    -DSINGLE_NBI -DTH_12713=NBI_READ -DBLM_0_ISLAND_ILA48 -DBLM_INIT_EMU_RINGS \
    -I${NETRONOME}/components/standardlibrary/include \
    -I${NETRONOME}/components/standardlibrary/microcode/include \
    -I${NETRONOME}/components/standardlibrary/microcode/src \
    -I${TEST_BUILD_DIR}/../../apps/nic -I${TEST_BUILD_DIR}/../../../include \
    -o  ${TEST_BUILD_DIR}/blm0.list \
    ${BLM_DIR}/blm_main.uc

    return $?
}

check_test_req () {
    ret=0

    FILE_BASE=`basename ${1%.*}`

    #Check if the test requires BLM
    if [[ -n `grep -E '[ \t]*(;|[\/\/])[ \t]*TEST_REQ_BLM$' ${1}` ]]; then
        build_blm
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            echo -n "${FILE_BASE}: "
            echo -e "${COLOR_WARN}SKIPPED (Unable to compile BLM)${COLOR_RESET}"
        fi
    else
        BLM_LINK=
    fi

    #Check if the test requires a soft reset
    if [[ -n `grep -E '[ \t]*(;|[\/\/])[ \t]*TEST_REQ_RESET$' ${1}` ]]; then
        msg=`nfp-nsp -R`
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            echo -n "${FILE_BASE}: "
            echo -e "${COLOR_WARN}SKIPPED (Soft reset failed with $msg)${COLOR_RESET}"
        fi
    fi

    return $ret
}

COLOR_PASS=${COLOR_PASS:-"\033[1;32m"}
COLOR_FAIL=${COLOR_FAIL:-"\033[1;31m"}
COLOR_WARN=${COLOR_WARN:-"\033[1;33m"}
COLOR_RESET=${COLOR_RESET:-"\e[0m"}

for t in `find ${TEST_DIR} -iname '*_test.uc' -o -iname '*_test.c'` ; do
    if echo ${t} | grep -v ${FILTER} > /dev/null ; then
        continue
    fi
    FILE_BASE=`basename ${t%.*}`

    #Check if the requirements for this test are met, if not, skip
    check_test_req $t
    if [[ $? -ne 0 ]]; then
        SKIPPED=$(( ${SKIPPED} + 1 ))
        continue
    fi

    if echo ${t} | grep '.uc' > /dev/null ; then
        nfas -Itest/include -Itest/lib $* -o ${TEST_BUILD_DIR}/${FILE_BASE}.list $t || exit 1
        nfld -chip nfp-4xxx-b0 -mip -rtsyms -map -u i32.me0 ${TEST_BUILD_DIR}/${FILE_BASE}.list $BLM_LINK || exit 1
    else
        nfcc -chip nfp-4xxx-b0 -v1 -Qno_decl_volatile -Itest/include -Itest/lib $* -o ${TEST_BUILD_DIR}/${FILE_BASE}.list $t || exit 1
        nfld -chip nfp-4xxx-b0 -mip -rtsyms -map -u i32.me0 ${TEST_BUILD_DIR}/${FILE_BASE}.list $BLM_LINK || exit 1
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
        elif [[ ${RESULT} -eq "0xfb" ]] ; then
            TESTED_64=`nfp-rtsym i32.me0._assert_fail_tested_64 | cut -c 16-`
            EXPECTED_64=`nfp-rtsym i32.me0._assert_fail_expected_64 | cut -c 16-`
            DETAIL=`printf -- "- expected %s, got %s" "${EXPECTED_64}" "${TESTED_64}"`
        elif [[ ${RESULT} -eq "0xfd" ]] ; then
            TESTED_64=`nfp-rtsym i32.me0._assert_fail_tested_64 | cut -c 16-`
            DETAIL=`printf -- "- unexpectedly got %s" "${TESTED_64}"`
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
if [[ ${FAILED} -eq 0 ]] && [[ ${PASSED} -ge 1 ]] && [[ ${SKIPPED} -eq 0 ]]; then
    echo -e "Summary : ${COLOR_PASS}${PASSED} passed, no failures${COLOR_RESET}"
    exit 0
elif [[ ${SKIPPED} -ge 1 ]]; then
    echo -e "Summary : ${COLOR_WARN}${PASSED} passed, ${SKIPPED} skipped, ${FAILED} failed${COLOR_RESET}"
    exit 0
else
    echo -e "Summary : ${COLOR_WARN}${PASSED} passed, ${SKIPPED} skipped, ${FAILED} failed${COLOR_RESET}"
    exit 1
fi
