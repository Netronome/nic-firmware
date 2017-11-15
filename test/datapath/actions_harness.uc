#ifndef _ACTIONS_HARNESS_UC
#define _ACTIONS_HARNESS_UC

#include <actions.uc>
#include <test.uc>

.if (0)
    tx_errors_offset#:
    drop#:
    egress#:
    actions#:
    test_fail()
    .reentry
    br[ebpf_reentry#]
.endif

#endif
