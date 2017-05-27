TEST_DIR=$1
shift
BUILD_DIR=$1
mkdir -p ${BUILD_DIR}
shift
#set -x
for t in `find ${TEST_DIR} -iname '*.uc'` ; do
    FILE_BASE=`basename ${t%.*}`
    nfas -Itest/include $* -o ${BUILD_DIR}/${FILE_BASE}.list $t || exit 1
    nfld -chip nfp-4xxx-b0 -mip -rtsyms -u i32.me0 ${BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw unload || exit 1
    nfp-nffw load -S ${BUILD_DIR}/${FILE_BASE}.nffw || exit 1
    awk '$0~/^;INIT_EXEC/{system(gensub("^;INIT_EXEC ", "", 1))}' < ${BUILD_DIR}/${FILE_BASE}.list || exit 1
    nfp-nffw start
    TIMEOUT=100
    while [[ `nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2` -eq "0" ]] ; do
       sleep 0.1
       TIMEOUT=$((TIMEOUT - 1))
       [[ ${TIMEOUT} -eq 0 ]] && break 
    done
    if [[ `nfp-reg mecsr:i32.me0.Mailbox0 | cut -d= -f2` -eq "1" ]] ; then
        echo ${FILE_BASE} : PASS
    else
        echo ${FILE_BASE} : FAIL
    fi 
done
