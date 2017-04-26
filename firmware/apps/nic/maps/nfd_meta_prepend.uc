#ifndef __NFD_PREPEND_META_UC
#define __NFD_PREPEND_META_UC

/* from disa.hg */


#include <nfd_user_cfg.h>
#include <nfp_net_ctrl.h>			; use file from nfp-nic
#include <ov.uc>

#ifndef NFP_NET_META_FIELD_SIZE
	#define NFP_NET_META_FIELD_SIZE	4
	#define NFP_NET_META_HASH        1 /* next field carries hash type */
	#define NFP_NET_META_MARK        2
#endif

#ifndef NFD_META_MAX_LW
	#define NFD_META_MAX_LW NFP_NET_META_FIELD_SIZE
#endif
#ifndef NFP_NET_META_FIELD_MASK
	#define_eval NFP_NET_META_FIELD_MASK ((1 << NFP_NET_META_FIELD_SIZE) - 1)
#endif
#ifndef NFP_NET_META_REPR
	#define NFP_NET_META_REPR 5
#endif

#macro nfd_in_meta_parse(out_pkt_data, in_meta_len, in_addr, READ_LW, NOT_CTRL_MSG_LABEL)
.begin
    .reg read $prepend_meta[NFD_META_MAX_LW]
    .xfer_order $prepend_meta
    .reg offset
    .reg xfer_addr
    .reg meta_field_types
    .reg meta_len
    .reg field_type
    .sig read_sig

    move(meta_len, in_meta_len)
    .if(meta_len > 0)
        alu[offset, NFD_IN_DATA_OFFSET, -, meta_len]

        mem[read32, $prepend_meta[0], offset, in_addr, <<8, READ_LW], ctx_swap[read_sig]

        move(meta_field_types, $prepend_meta[0])

        alu[xfer_addr, (&$prepend_meta[1] << 2), OR, ctx_num, <<7]
        local_csr_wr[T_INDEX, xfer_addr]
        alu[meta_len, meta_len, -, 1]

        .while ((meta_field_types != 0) && (meta_len != 0))

            alu[field_type, meta_field_types, and, NFP_NET_META_FIELD_MASK]

            #define_eval __MAX_JUMP (NFP_NET_META_FIELD_MASK)
            preproc_jump_targets(j, __MAX_JUMP)

            jump[field_type, j0#], targets[PREPROC_LIST]

            #ifdef NFD_META_LOOP
                #error "NFD_META_LOOP is already defined" (NFD_META_LOOP)
            #endif
            #define NFD_META_LOOP 0
            #while (NFD_META_LOOP < __MAX_JUMP)
                j/**/NFD_META_LOOP#:
                    br[s/**/NFD_META_LOOP#]
                #define_eval NFD_META_LOOP (NFD_META_LOOP + 1)
            #endloop
            #undef NFD_META_LOOP
            #undef __MAX_JUMP

            s/**/0#:
            s/**/3#:
            s/**/4#:
                br[next#]

            s/**/NFP_NET_META_HASH#:	// not supported yet
            s/**/NFP_NET_META_MARK#:
                alu[--, --, b, *$index++]
                br[next#]

            s/**/NFP_NET_META_REPR#:
				.reg cmsg_port
				move(cmsg_port, CMSG_PORT)
				alu[--, cmsg_port, -, *$index++]
				beq[ret#]
				br[NOT_CTRL_MSG_LABEL]

            s/**/6#:
            s/**/7#:
            s/**/8#:
            s/**/9#:
            s/**/10#:
            s/**/11#:
            s/**/12#:
            s/**/13#:
            s/**/14#:
            s/**/15#:
            next#:

            alu[meta_len, meta_len, -, 1]
            alu[meta_field_types, --, b, meta_field_types, >>NFP_NET_META_FIELD_SIZE]
        .endw
    .endif
	br[NOT_CTRL_MSG_LABEL]
ret#:
.end
#endm

#macro nfd_out_meta_prepend(io_pkt_len, io_offset, io_meta_len, in_meta_field, in_addr, IN_META_FIELD_TYPE, IN_LAST_IO)
.begin

    #if (strstr("|YES|NO|", '|IN_LAST_IO|') == 0)
        #error "IN_LAST_IO must be YES or NO" (IN_LAST_IO)
    #endif

    .reg temp
    .reg $prepend_meta[2]
    .xfer_order $prepend_meta
    .sig sig_write

    move($prepend_meta[1], in_meta_field)

    .if(io_meta_len > 0) /* some fields already there */
        alu[io_offset, io_offset, - , io_meta_len]
        mem[read32, $prepend_meta[0], io_offset, in_addr, <<8, 1], ctx_swap[sig_write]

        alu[$prepend_meta[0], IN_META_FIELD_TYPE, or, $prepend_meta[0], <<NFP_NET_META_FIELD_SIZE]

        alu[io_meta_len, io_meta_len, +, 4]
        alu[io_pkt_len, io_pkt_len, +, 4]
        alu[io_offset, io_offset, -, 4]
    .else
        move($prepend_meta[0], IN_META_FIELD_TYPE]
        alu[io_meta_len, io_meta_len, +, 8]
        alu[io_pkt_len, io_pkt_len, +, 8]
        alu[io_offset, io_offset, -, 8]
    .endif

    #if (streq('|IN_LAST_IO|', "|NO|"))
        mem[write32, $prepend_meta[0], io_offset, in_addr, <<8, 2], ctx_swap[sig_write]
    #else
        .sig sig_read
        mem[write32, $prepend_meta[0], io_offset, in_addr, <<8, 2], sig_done[sig_write]
        mem[read32, $prepend_meta[0], io_offset, in_addr, <<8, 2], sig_done[sig_read]
        ctx_arb[sig_write, sig_read]
    #endif
.end
#endm


#endif /* __NFD_PREPEND_META_UC */


