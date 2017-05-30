#ifndef __TEST_UC
#define __TEST_UC


#macro test_pass()
    local_csr_wr[MAILBOX_0, 0x01]
    ctx_arb[kill]
#endm


#macro test_fail(fail_type)
.begin
    .reg sts
    local_csr_wr[MAILBOX_0, fail_type]
    local_csr_rd[ACTIVE_CTX_STS]
    immed[sts, 0]
    local_csr_wr[MAILBOX_1, sts]
    ctx_arb[kill]
.end
#endm


#macro test_fail()
    test_fail(0xff)
#endm


#macro test_assert_equal(tested, expected)
    .if_unsigned(tested != expected)
        local_csr_wr[MAILBOX_2, tested]
        local_csr_wr[MAILBOX_3, expected]
        test_fail(0xfc)
    .endif
#endm

#endif

