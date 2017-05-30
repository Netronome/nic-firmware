TEST_DIR=$1
shift
BUILD_DIR=$1
mkdir -p ${BUILD_DIR}
shift
#set -x
for t in `find ${TEST_DIR} -iname '*_test.uc'` ; do
    FILE_BASE=`basename ${t%.*}`
    nfas -Itest/include -I test/lib $* -o ${BUILD_DIR}/${FILE_BASE}.list $t || exit 1
    nfld -chip nfp-4xxx-b0 -mip -rtsyms -u i32.me0 ${BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw unload || exit 1
    nfp-nffw load -S ${BUILD_DIR}/${FILE_BASE}.nffw || exit 1
    awk '$0~/;TEST_INIT_EXEC/{system(gensub(";TEST_INIT_EXEC ", "", 1))}' < ${BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw start
    TIMEOUT=100
    while [[ `nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2` -eq "0" ]] ; do
       sleep 0.1
       TIMEOUT=$((TIMEOUT - 1))
       [[ ${TIMEOUT} -eq 0 ]] && break 
    done
    RESULT=`nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2`
    if [[ ${RESULT} -eq "1" ]] ; then
        echo ${FILE_BASE} : PASS
    else
        if [[ ${RESULT} -eq "0xfc" ]] ; then
           TESTED=`nfp-reg mecsr:i32.me0.Mailbox2 | cut -d= -f2`
           EXPECTED=`nfp-reg mecsr:i32.me0.Mailbox3 | cut -d= -f2`
           DETAIL+=`printf -- "- expected 0x%08x, got 0x%08x" ${EXPECTED} ${TESTED}`
        fi
        STS=`nfp-reg mecsr:i32.me0.mailbox_1 | cut -d= -f2`
        PC=$(( (STS >> 8) & 0x1ffff ))
        ISL=$(( (STS >> 25) & 0x3f ))
        ME=$(( ((STS >> 3) & 0xf) - 4 ))
        CTX=$(( STS & 0x7 ))
        echo ${FILE_BASE} : FAIL @ i${ISL}.me${ME}.ctx${CTX}:${PC} ${DETAIL}
    fi 
done
