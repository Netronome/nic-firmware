/*
    test support functions
*/

#include <nfp.h>
#include <rtl.h>

/* stop all threads except thread 0 */
__intrinsic void single_ctx_test() {
    uint32_t sts = local_csr_read(local_csr_active_ctx_sts);
    if (sts & 7 )
        __asm ctx_arb[kill];
}

/* test passed */
__intrinsic void test_pass() {
    local_csr_write(local_csr_mailbox0, 0x01);
}

/* test failed with fail code */
__intrinsic _test_fail(uint32_t fail_type) {
    uint32_t sts = local_csr_read(local_csr_active_ctx_sts);
    local_csr_write(local_csr_mailbox0, fail_type);
    local_csr_write(local_csr_mailbox1, sts);
    __asm ctx_arb[kill];
}

/* test failed, code set to 0xff */
__intrinsic void test_fail() {
    _test_fail(0xff);
}

/* assert (fail test zero value) */
__intrinsic void test_assert(uint32_t _assert) {
    if (!_assert)
        _test_fail(0xfa);
}

/* assert when values are not equal */
__intrinsic void test_assert_equal(uint32_t tested,
                                   uint32_t expected) {
    if ( tested != expected ) {
        local_csr_write(local_csr_mailbox2, tested);
        local_csr_write(local_csr_mailbox3, expected);
        _test_fail(0xfc);
    }
}

/* assert when values are equal */
__intrinsic void test_assert_unequal(uint32_t tested,
                                     uint32_t expected) {
    if ( tested == expected ) {
        local_csr_write(local_csr_mailbox2, tested);
        _test_fail(0xfe);
    }
}
