#macro pkt_write_mod_script(out_script_offset, in_pkt_base, in_pkt_offset, ERROR_LABEL)
.begin
    .reg offset_table // stores the inverse of legal script offsets, 4 bits per entry
    .reg ideal_offset
    .reg delta
    .reg shift
    .reg tmp

    .reg $script[3]
    .xfer_order $script

    .sig sig_write
    .sig sig_read

    // Lookup legal packet modifier script offset in 32-bit table indexed by ideal offset
    alu[ideal_offset, in_pkt_offset, -, 8]
    immed[offset_table, 0x1c58] // the zeroes we don't init are max offset due to inverse
    alu[shift, 0x1c, AND, ideal_offset, >>3]
    alu[offset_table, shift, B, offset_table, <<4]
    alu[out_script_offset, 0x78, AND~, offset_table, >>indirect]

    // unsupported packet offsets (below 40) get allocated the largest offset to make this test negative
    alu[delta, ideal_offset, -, out_script_offset]
    bmi[ERROR_LABEL]

    // special handling for offsets larger than 48
    alu[tmp, delta, +, (128 + 64 + 15)] // need +15 to handle zero delta special case for offset_len
    br!=byte[tmp, 1, 0, large_offset#], defer[2] // delta > 48 overflows into 2nd byte

        alu[tmp, 0x3, AND, tmp, >>4] // offset_len = ((delta + 15) / 16) % 4 (modulo to clear added bits)
        alu[tmp, (1 << 6), OR, tmp, <<24] // rdata_loc = 1

    alu[$script[0], tmp, OR, delta, <<16]  // opcode_index
    immed[$script[1], 0x1020, <<8] // unused offsets become part of script pad

    mem[write32, $script[0], in_pkt_base, <<8, out_script_offset, 2], sig_done[sig_write]
    mem[read32, $script[0], in_pkt_base, <<8, out_script_offset, 1], sig_done[sig_read]
    ctx_arb[sig_read, sig_write], br[done#]

large_offset#:
    // max supported delta = 7*16 + 8 (allowing for pad packet opcode)
    alu[--, 120, -, delta]
    bmi[ERROR_LABEL]

    alu[tmp, (1 << 6), OR, tmp, <<24] // rdata_loc = 1
    alu[$script[0], tmp, OR, delta, <<16] // opcode_index

    // how do we delete range 40-48 using these offsets?, first insert 8/16 bytes?
    immed[tmp, 0x1020, <<8]
    alu[$script[1], tmp, OR, 0x30]

    immed[tmp, 0x4050, <<16]
    alu[$script[2], tmp, OR, 0x60, <<8]

    mem[write32, $script[0], in_pkt_base, <<8, out_script_offset, 3], sig_done[sig_write]
    mem[read32, $script[0], in_pkt_base, <<8, out_script_offset, 1], sig_done[sig_read]
    ctx_arb[sig_read, sig_write]

done#:
.end
#endm
