#ifndef _NFD_CREDIT_CACHE_H
#define _NFD_CREDIT_CACHE_H

#include <nfd_out.uc>
#include <ov.uc>

#ifndef NFD_CC_BATCH_SIZE
    #define NFD_CC_BATCH_SIZE   1
#endif

#define NFD_CC_ENTRIES          16

#if (NFD_CC_BATCH_SIZE == 1)

#macro nfd_cc_acquire(in_pcie, in_queue, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo

    .reg read $credits
    .sig sig_credits

#if isnum(in_pcie)
    immed[addr_hi, (((NFD_PCIE_ISL_BASE + in_pcie) | __NFD_DIRECT_ACCESS) << 8), <<16]
#else
    alu[addr_hi, (NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS), +, in_pcie]
    alu[addr_hi, --, B, addr_hi, <<24]
#endif

#if isnum(in_queue)
    immed[addr_lo, (in_queue <<  log2(NFD_OUT_ATOMICS_SZ))]
#else
    alu[addr_lo, --, B, in_queue, <<(log2(NFD_OUT_ATOMICS_SZ))]
#endif

    ov_start(OV_IMMED8)
    ov_set_use(OV_IMMED8, 1)
    ov_clean()
    mem[test_subsat_imm, $credits, addr_hi, <<8, addr_lo, 1], indirect_ref, sig_done[sig_credits]
    ctx_arb[sig_credits]

    alu[--, --, B, $credits]
    beq[FAIL_LABEL]

.end
#endm

#else // NFD_CC_BATCH_SIZE

#error this implementation is incomplete, mechanism is required to free cached credits when NFD queue is reset

.alloc_mem nfd_cc_base lm+0 me (NFD_CC_ENTRIES * 4) (NFD_CC_ENTRIES * 4)

// implicit init on #include
.if (ctx() == 0)
.begin
    .reg entry
    .reg value

    immed[entry, 0]
    immed[value, 0xffffffff]
    .while (entry < 16)
        cam_write[entry, value, 0]
        alu[value, value, -, 1]
        alu[entry, entry, +, 1]
    .endw
.end
.endif

#macro nfd_cc_acquire(in_pcie, in_queue, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg entry
    .reg lm_addr
    .reg result
    .reg tag

    .reg read $credits
    .sig sig_credits

#if (isnum(in_pcie) && in_pcie == 0)
retry#:
    cam_lookup[result, in_queue]
#else
    .reg key
    #if ((isnum(in_queue) && isnum(in_pcie)) || (isnum(in_queue) && in_queue > 0xff))
        immed[key, in_queue]
        alu[key, key, OR, in_pcie, <<24]
    #else
        alu[key, in_queue, OR, in_pcie, <<24]
    #endif
retry#:
    cam_lookup[result, key]
#endif

    alu[lm_addr, 0x3c, AND, result, >>1]
    local_csr_wr[ACTIVE_LM_ADDR_0, lm_addr]
        br_bset[result, 8, busy#]
        br_bclr[result, 7, evict#], defer[1]
            alu[entry, 0xf, AND, result, >>3]
    alu[*l$index0, *l$index0, -, 1]
    bge[done#]

    #if (isnum(in_pcie))
        immed[addr_hi, (((NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS) + in_pcie) << 8), <<16]
    #else
        alu[addr_hi, (NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS), +, in_pcie]
        alu[addr_hi, --, B, addr_hi, <<24]
    #endif

    #if (isnum(in_queue))
        immed[addr_lo, (in_queue <<  log2(NFD_OUT_ATOMICS_SZ))]
    #else
        alu[addr_lo, --, B, in_queue, <<(log2(NFD_OUT_ATOMICS_SZ))]
    #endif

    ov_single(OV_IMMED8, NFD_CC_BATCH_SIZE)
    mem[test_subsat_imm, $credits, addr_hi, <<8, addr_lo, 1], indirect_ref, sig_done[sig_credits]
    ctx_arb[sig_credits], defer[2], br[check_credits#]
        cam_write_state[entry, 1] // set busy before swapping
        nop_volatile

    busy#:
        ctx_arb[voluntary], br[retry#]

    evict#:
        cam_read_tag[tag, entry]
        alu[addr_hi, tag, AND, 0xff, <<24]
        alu[addr_hi, addr_hi, OR, (NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS), <<24]
        alu[addr_lo, 0, +16, tag]
        alu[addr_lo, --, B, addr_lo, <<(log2(NFD_OUT_ATOMICS_SZ))]
        ov_single(OV_IMMED8, *l$index0)
        mem[add_imm, --, addr_hi, <<8, addr_lo, 1], indirect_ref
        br[fetch#]

    small_batch#:
        br=byte[$credits, 0, 0, FAIL_LABEL#]
        br[ok#], defer[1]
            alu[*l$index0, $credits, -, 1]

    check_credits#:
        alu[--, $credits, -, NFD_CC_BATCH_SIZE]
        bmi[small_batch#], defer[1]
            cam_write_state[entry, 0]

        alu[*l$index0, NFD_CC_BATCH_SIZE, -, 1]

done#:
.end
#endm

#endif // NFD_CC_BATCH_SIZE

#endif
