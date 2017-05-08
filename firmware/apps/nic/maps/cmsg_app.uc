/*
 * CMSG receive handler main function
 */


#define NUM_CONTEXT 4
.num_contexts 4

#ifndef PKT_COUNTER_ENABLE
    #define PKT_COUNTER_ENABLE
    #include "pkt_counter.uc"
#endif

#define DEBUG_TRACE
#define CMSG_UNITTEST_CODE
#define JOURNAL_ENABLE 1
#include "hashmap.uc"
#include "cmsg_map.uc"
#include "map_debug_config.h"
cmsg_init()


.begin
    .reg ctx_num
	.reg @cmsg_rx_cntr
	.reg @cmsg_rx_init

	.if (ctx() == 0)
		local_csr_wr[MAILBOX0, 0xf]
		local_csr_wr[MAILBOX1, 0xe]
		local_csr_wr[MAILBOX2, 0xe]
		local_csr_wr[MAILBOX3, 0xd]
		move(@cmsg_rx_init, 0)
		move(@cmsg_rx_cntr, 0)
    .endif

    local_csr_rd[ACTIVE_CTX_STS]
    immed[ctx_num, 0]
    alu[ctx_num, ctx_num, and, 7]

    local_csr_wr[MAILBOX3, 1]
	alu[@cmsg_rx_init, @cmsg_rx_init, +, 1]
    local_csr_wr[MAILBOX2, @cmsg_rx_init]

	local_csr_wr[MAILBOX0, 0]
	local_csr_wr[MAILBOX1, 0]

main_loop#:
    cmsg_rx()
	alu[@cmsg_rx_cntr, 1, +, @cmsg_rx_cntr]
    local_csr_wr[MAILBOX0, @cmsg_rx_cntr]

    br[main_loop#]

done#:
ctx_arb[kill]

.end
