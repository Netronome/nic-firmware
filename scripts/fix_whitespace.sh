#!/bin/bash

# Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

find ./ -iname '*.h' -exec sed -i 's/[[:space:]]\+$//' {} \;
find ./ -iname '*.c' -exec sed -i 's/[[:space:]]\+$//' {} \;
find ./ -iname '*.uc' -exec sed -i 's/[[:space:]]\+$//' {} \;
find ./ -iname '*.h' -exec sed -i 's/\t/    /g' {} \;
find ./ -iname '*.c' -exec sed -i 's/\t/    /g' {} \;
find ./ -iname '*.uc' -exec sed -i 's/\t/    /g' {} \;

