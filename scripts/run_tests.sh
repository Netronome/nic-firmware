FILTER=$1
shift
TEST_DIR=$1
shift
BUILD_DIR=$1
mkdir -p ${BUILD_DIR}
shift
#set -x
PASSED=0
FAILED=0
for t in `find ${TEST_DIR} -iname '*_test.uc'` ; do
    if echo ${t} | grep -v ${FILTER} > /dev/null ; then
        continue
    fi
    FILE_BASE=`basename ${t%.*}`
    nfas -Itest/include -I test/lib $* -o ${BUILD_DIR}/${FILE_BASE}.list $t || exit 1
    nfld -chip nfp-4xxx-b0 -mip -rtsyms -u i32.me0 ${BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw unload || exit 1
    nfp-nffw load -S ${BUILD_DIR}/${FILE_BASE}.nffw || exit 1
    awk '$0~/;TEST_INIT_EXEC/{system(gensub(";TEST_INIT_EXEC ", "", 1))}' < ${BUILD_DIR}/${FILE_BASE}.list || exit 1
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
        echo -e "\033[1;32mPASS" ; tput sgr0
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
        echo -en "\033[1;31mFAIL " ; tput sgr0
        if [[ ${RESULT} -eq 0 ]] ; then
            echo "(timed out)"
        else
            echo "@ i${ISL}.me${ME}.ctx${CTX}:${PC} ${DETAIL}"
        fi
        FAILED=$(( ${FAILED} + 1 ))
    fi 
done
if [[ ${FAILED} -eq 0 ]] && [[ ${PASSED} -ge 1 ]] ; then
    echo -e "Summary : \033[1;32m${PASSED} passed, no failures" ; tput sgr0
    exit 0
else
    echo -e "Summary : \033[1;33m${PASSED} passed, ${FAILED} failed" ; tput sgr0
    exit 1
fi
