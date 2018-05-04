#include <single_ctx_test.uc>

#include <global.uc>

.reg rand1
.reg rand2

local_csr_rd[PSEUDO_RANDOM_NUMBER]
immed[rand1, 0]

test_assert_unequal(rand1, 0)

local_csr_rd[PSEUDO_RANDOM_NUMBER]
immed[rand2, 0]

test_assert_unequal(rand1, rand2)

test_pass()
