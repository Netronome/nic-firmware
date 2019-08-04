/*
 * Copyright (C) 2015-2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   trng.uc
 * @brief  True Random Number Generator Macros
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

 #include <assert.h>
 #include <nfp.h>
 #include <nfp_chipres.h>

 #include <stdint.h>

 #include <platform.h>

 #include <nfp/me.h>
 #include <nfp/mem_bulk.h>
 #include <nfp/mem_ring.h>
 #include <nfp/mem_atomic.h>
 #include <nfp/cls.h>

 #include <nfp6000/nfp_me.h>

 #include <std/reg_utils.h>

 #include "trng.h"


 /*
  * init the TRNG
  *
  */
__intrinsic void
trng_init()
{
    uint32_t r_tmp;
    uint32_t r_cl_num;
    uint32_t r_xpb_address;
    __xread unsigned int xfr_rd[2];
    __xwrite unsigned int xfr_wr[2];
    SIGNAL s1;

    /* This is from the EAS
     *
     * The standard operational mode
     *  1. Request a reset of the asynchronous seed generator
     *  2. Load the async seed generator LFSR with a suitable value (anything non-zero)
     *  3. Load the async seed generator incrementer with 1 (so that a maximum bitstream is generated)
     *  4. Configure the asynchronous seed generator to continually generate entropy for the ring oscillator.
     *  5. Configure the ring oscillator to run in a static feedback mode
     *  6. Set the LFSR to reseed the ring oscillator continually
     *  7. Configure the PRNG LFSRs should to reseed in the order of every 100,000 cycles.
     *  8. The 'whiteness period' timer should be set to 64000 with a max ones of 40000 and a min ones of 24000
     *  9. The 'whitener' should be configured with one of the three standard mappings included below.
     * 10. The data rate timer should be set to 512, so that 64 bits of whitened data is ready every 512 cycles (a
           generated bit rate of 1/8th of the bus clock)
     * 11. Alerts should be cleared
     * 12. The write lockout bit should be set.
     * 13. Wait for 400,000 cycles or more; this permits the entropy to feed in to the LFSRs.
     * 14. Write to the SSB to clear any data
     * 15. Data is then ready to be read from the SSB at the given rate specified by the data rate timer.
     *
     */

    // address[30]    specifies Global/Local XPB select (0: Local XPB, 1: Global XPB),
    // address[29:24] the Island number of XPB target (if 0: use own island ID),
    // address[23:22] the slave XPB Slave ID (when accessing XPB Slave Island),
    // address[21:16] the XPB Device ID number of XPB target,
    // address[15:2]  the XPB Target Register address of the first 32-bit register
    //                to be accessed in the burst
    //                Ring_n_Base = 0x100 + n*0x10
    //                Ring_n_Head = 0x104 + n*0x10
    //                Ring_n_Tail = 0x108 + n*0x10

    // 0 : 0 : 000000 : 00 : 001000 : 0x01mm
    // 0000000000001000 : 0x0100
    // 0000 0000 0000 1000 : 0x01mm
    // 0    0    0    8    : 0x01mm
    // 0x000801mm

    r_cl_num = local_csr_read(local_csr_active_ctx_sts);
    r_cl_num = 0x3F & (r_cl_num >>25);  // IslandID = 30:25

    //#define CLS_TRNG_XPB_DEVICE_ID 12
    // Bit[31]=1 means do XPB access  ?????????????
    // Bit[29:24]=Island number
    r_xpb_address = ((CLS_TRNG_XPB_DEVICE_ID <<16) | (1<<31) | (r_cl_num <<24));

    xfr_wr[1] = 0;

    // Reset the FSM
    xfr_wr[0] = 2;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_ASYNC_CMD, 1], ctx_swap[s1]

    sleep(5);
    // Reset the async generator
    xfr_wr[0] = 1;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_ASYNC_CMD, 1], ctx_swap[s1]

    sleep(5);

    // Write Async Ring control reg
    // No overrides, feedback on closest tap, sync enabled, ring enabled, entropy enabled
    xfr_wr[0] = 0x87;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_ASYNC_RING, 1] ,ctx_swap[s1]

    // Write Async Test reg
    // NEW = 1,  OLD = 0 Test data off - no leaking data!
    xfr_wr[0] = 0x1;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_ASYNC_TEST, 1], ctx_swap[s1]

    // Write Async Config reg
    // Initial seed for LFSR and INCR non-zero
    xfr_wr[0] = (0xff00 <<16);  // EAS says bit 31 is RESERVED !!
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_ASYNC_CFG, 1], ctx_swap[s1]

    // Write LFSR Config reg
    // PRNGs all to be reseeded with XOR every 0x1000 cycles
    r_tmp = 0x0AAF;
    xfr_wr[0] = r_tmp | (1 <<28);
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_LFSR_CFG, 1], ctx_swap[s1]

    // Write Whitener Control reg
    // Whitener enabled, using standard path; timer at 0x4000
    r_tmp = 0x2;
    xfr_wr[0] = r_tmp | (4 <<28);
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_WHITEN_CONTROL, 1], ctx_swap[s1]

    // Write Whitener Config reg
    // 0x83388338,
    r_tmp = 0x83388338;
    xfr_wr[0] = r_tmp;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_WHITEN_CONFIG, 1], ctx_swap[s1]

    // period = 100000 = 0x1_86A0
    // self.wr_monitor_period( period  )          100,000 = 0x186A0                // 2,000
    // self.wr_monitor_min_ones( period/4*0.90 )  100,000/4 *.9 = 22,500 = 0x57E4  //   450
    // self.wr_monitor_max_ones( period/4*1.10 )  100,000/4*1.1 = 27,500 = 0x6B6C  //   550

    xfr_wr[0] = 2000;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_MON_PERIOD, 1], ctx_swap[s1]

    xfr_wr[0] = 450;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_MON_ONES_MIN, 1], ctx_swap[s1]

    xfr_wr[0] = 550;
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_MON_ONES_MAX, 1], ctx_swap[s1]

    // Write Monitor Run Length reg
    // Chances of 64 in a row is, er, small
    xfr_wr[0] = (64 <<16);
    __asm ct[xpb_write, xfr_wr[0], r_xpb_address, TRNG_MON_MAX_RUN_LEN, 1], ctx_swap[s1]

    // Run async generator repeatedly, loading the incrementer each time
    xfr_wr[0] = 6;
    __asm ct[xpb_write ,xfr_wr[0], r_xpb_address, TRNG_ASYNC_CMD, 1], ctx_swap[s1]

    sleep(200);

    // XPB read Alert Status
    __asm ct[xpb_read, xfr_rd[0], r_xpb_address, TRNG_ALERT, 1], ctx_swap[s1]

    //* 13. Wait for 400,000 cycles or more; this permits the entropy to feed in to the LFSRs.
    sleep(400000);

    xfr_wr[0] = 0;
    xfr_wr[1] = 0;
    cls_write(&xfr_wr[0], (__cls void *) CLS_PERIPHERAL_TRNG_DATA, sizeof(xfr_wr));

}

__intrinsic void
trng_rd64(uint32_t *trng_hi, uint32_t *trng_lo)
{

    __xread uint32_t xfr[2];

    do {
        cls_read(&xfr[0], (__cls void *) CLS_PERIPHERAL_TRNG_DATA, sizeof(xfr));
    } while ((xfr[0] == 0) || (xfr[1] == 0));

    *trng_lo = xfr[0];
    *trng_hi = xfr[1];
}
