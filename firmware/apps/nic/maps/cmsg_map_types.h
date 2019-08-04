/*
 * Copyright (c) 2017-2019 Netronome Systems, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _MAP_CTL_MSG_TYPES_H_
#define _MAP_CTL_MSG_TYPES_H_

#define CMSG_MAP_VERSION	1

#ifndef CMSG_PORT
	#define CMSG_PORT		0xffffffff
#endif

#define HASHMAP_MAX_TID 255  /* must agree with same definition in hashmap.uc,
                                or include this file in hashmap.uc */

//SR-IOV VLAN-MAC Table ID
#define SRIOV_TID               (HASHMAP_MAX_TID - 1)

/*
 * enhancement:  add field length to support variable size
 */

/**
 * Format of the control message in MU
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +---------------+---------------+---------------+---------------+
 *    0  |    cmsg_type  |     version   |            tag                | <- General cmsg header
 *       +---------------+---------------+---------------+---------------+
 *    1  |                         data                                  | <- specific to this msg
 *       +-------------------------------+---------------+---------------+
 *                                     ...
 *       +---------------------------------------------------------------+
 *       |                                                               |
 *       +---------------------------------------------------------------+
 *
 **
 *   map_alloc request
 *       +---------------------------------------------------------------+
 *    1  |    key size                                                   |
 *       +---------------------------------------------------------------+
 *    2  |    value size                                                 |
 *       +---------------------------------------------------------------+
 *    3  |    max entries                                                |
 *       +---------------------------------------------------------------+
 *    4  |    map_flags                                                  |
 *       +---------------------------------------------------------------+
 *   map_alloc reply
 *       +---------------------------------------------------------------+
 *    1  |    map fd (0 success)                                         |
 *       +---------------------------------------------------------------+
 *    2  |    fd (0 is error)                                            |
 *       +---------------------------------------------------------------+
 *
 *   map_free request
 *       +---------------------------------------------------------------+
 *    1  |    map fd                                                     |
 *       +---------------------------------------------------------------+
 *   map_free reply
 *       +---------------------------------------------------------------+
 *    1  |    0		                                                     |
 *       +---------------------------------------------------------------+
 *    2  |    number of entries deleted	                                 |
 *       +---------------------------------------------------------------+
 *
 *
 *	map_lookup_elem request
 *       +---------------------------------------------------------------+
 *    1  |    map fd                                                     |
 *       +---------------------------------------------------------------+
 *    2  |    key word 0                                                 |
 *       +---------------------------------------------------------------+
 *    3  |    key word 1                                                 |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |    key word 9                                                 |
 *       +---------------------------------------------------------------+
 * map_lookup_elem reply
 *       +---------------------------------------------------------------+
 *    1  |    rc (0 found)                                               |
 *       +---------------------------------------------------------------+
 *    2  |    value word 0                                               |
 *       +---------------------------------------------------------------+
 *    3  |    value word 1                                               |
 *       +---------------------------------------------------------------+
 *       |    ...                                                        |
 *       +---------------------------------------------------------------+
 *    7  |    value word 5                                               |
 *       +---------------------------------------------------------------+
 *
 *  map_update_elem request
 *       +---------------------------------------------------------------+
 *    1  |   map fd                                                      |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *   12  |   value word 0                                                |
 *       +---------------------------------------------------------------+
 *   13  |   value word 1                                                |
 *       +---------------------------------------------------------------+
 *       |     ....                                                      |
 *       +---------------------------------------------------------------+
 *   17  |   value word 5                                                |
 *       +---------------------------------------------------------------+
 *  map_update_elem reply
 *       +---------------------------------------------------------------+
 *    1  |  RC, 0=success                                                |
 *       +---------------------------------------------------------------+
 *
 *  map_get_next_key request
 *       +---------------------------------------------------------------+
 *    1  |   map fd                                                      |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *  map_get_next_key reply
 *       +---------------------------------------------------------------+
 *    1  |   RC, 0=success                                               |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *
 *  map_get_first request
 *       +---------------------------------------------------------------+
 *    1  |   map fd                                                      |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *  map_get_first reply
 *       +---------------------------------------------------------------+
 *    1  |   RC, 0=success                                               |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *
 *  map_delete_elem request
 *       +---------------------------------------------------------------+
 *    1  |   map fd                                                      |
 *       +---------------------------------------------------------------+
 *    2  |   key word 0                                                  |
 *       +---------------------------------------------------------------+
 *    3  |   key word 1                                                  |
 *       +---------------------------------------------------------------+
 *       |     ...                                                       |
 *       +---------------------------------------------------------------+
 *   11  |   key word 9                                                  |
 *       +---------------------------------------------------------------+
 *  map_delete_elem reply
 *       +---------------------------------------------------------------+
 *    1  |   RC                                                          |
 *       +---------------------------------------------------------------+
*/

/**
 * Types defined for map related control messages
 *
 */
#define CMSG_TYPE_MAP_ALLOC     1
#define CMSG_TYPE_MAP_FREE      2
#define CMSG_TYPE_MAP_LOOKUP    3
#define CMSG_TYPE_MAP_ADD       4
#define CMSG_TYPE_MAP_DELETE    5
#define CMSG_TYPE_MAP_GETNEXT   6
#define CMSG_TYPE_MAP_GETFIRST  7
#define CMSG_TYPE_PRINT			8
	/* CMSG_TYPE_MAP_ARRAY_GETNEXT is internal type */
#define CMSG_TYPE_MAP_ARRAY_GETNEXT  0xf6

#define CMSG_TYPE_MAP_START		1
#define CMSG_TYPE_MAP_MAX		7

//#define CMSG_TYPE_MAX (CMSG_TYPE_LAST_UNUSED)

#define CMSG_TYPE_MAP_ALLOC_REPLY		0x81
#define CMSG_TYPE_MAP_FREE_REPLY		0x82
#define CMSG_TYPE_MAP_LOOKUP_REPLY		0x83
#define CMSG_TYPE_MAP_ADD_REPLY			0x84
#define CMSG_TYPE_MAP_DELETE_REPLY		0x85
#define CMSG_TYPE_MAP_GETNEXT_REPLY		0x86
#define CMSG_TYPE_MAP_GETFIRST_REPLY	0x87

#define CMSG_TYPE_MAP_REPLY_BIT			7

#define CMSG_MAP_ALLOC_REQ_KEY_IDX		0
#define CMSG_MAP_ALLOC_REQ_VALUE_IDX	1
#define CMSG_MAP_ALLOC_REQ_MAX_IDX		2
#define CMSG_MAP_ALLOC_REQ_FLGS_IDX		3

#define CMSG_MAP_KEY_LW					 10
#define CMSG_MAP_VALUE_LW				  6
#define CMSG_MAP_KEY_VALUE_LW			 16
#define CMSG_MAP_KEY_VALUE_SZ            (CMSG_MAP_KEY_VALUE_LW * 4)

#define CMSG_RC_SUCCESS             0
#define CMSG_RC_ERR_MAP_FD          1
#define CMSG_RC_ERR_MAP_NOENT       2   /* ENOENT */
#define CMSG_RC_ERR_MAP_ERR         3   /* EINVAL used by cmsg */
#define CMSG_RC_ERR_MAP_PARSE       4   /* EIO */
#define CMSG_RC_ERR_MAP_EXIST       5   /* EEXIST used by cmsg */
#define CMSG_RC_ERR_NOMEM           6
#define CMSG_RC_ERR_ENOENT          2
#define CMSG_RC_ERR_E2BIG           7
#define CMSG_RC_ERR_EINVAL          22
#define CMSG_RC_ERR_EEXIST          17
#define CMSG_RC_ERR_ENOMEM          12

#define CMSG_OP_HDR_LW			4

#define CMSG_MAP_RC_IDX				1
#define CMSG_MAP_TID_IDX			1
#define CMSG_MAP_OP_COUNT_IDX		2
#define CMSG_MAP_OP_FLAGS_IDX		3

#define CMSG_MAP_ALLOC_KEYSZ_IDX	1
#define CMSG_MAP_ALLOC_VALUESZ_IDX	2
#define CMSG_MAP_ALLOC_MAXENT_IDX	3
#define CMSG_MAP_ALLOC_TYPE_IDX		4
#define CMSG_MAP_ALLOC_FLAGS_IDX	5

/* flags used for add/update */
#define CMSG_BPF_ANY     0 /* create new element or update existing */
#define CMSG_BPF_NOEXIST 1 /* create new element if it didn't exist */
#define CMSG_BPF_EXIST   2 /* update existing element */

#ifndef __NFP_LANG_ASM
struct cmsg_req_map_alloc_tbl {
	union {
		struct {
			uint32_t type:8;
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t key_size;		/* in bytes */
			uint32_t value_size;	/* in bytes */
			uint32_t max_entries;
			uint32_t map_type;
			uint32_t map_flags;		/* reserved */
		};
		uint32_t __raw[5];
	};
};
struct cmsg_reply_map_alloc_tbl {
	union {
		struct {
			uint32_t type:8;
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t rc;		/* 0 success */
			uint32_t tid;		/* 0 if error */
		};
		uint32_t __raw[3];
	};
};
struct cmsg_req_map_free_tbl {
	union {
		struct {
			uint32_t type:8;
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t tid;
		};
		uint32_t __raw[2];
	};
};
struct cmsg_reply_map_free_tbl {
	union {
		struct {
			uint32_t type:8;
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t rc;		/* 0 success */
		};
		uint32_t __raw[2];
	};
};

struct cmsg_key_value {
	union {
		struct {
			uint32_t key[CMSG_MAP_KEY_VALUE_LW];
			uint32_t value[CMSG_MAP_KEY_VALUE_LW];
		};
		uint32_t __raw[CMSG_MAP_KEY_VALUE_LW*2];
	};
};


struct cmsg_req_map_op {
	union {
		struct {
			uint32_t type:8;				/* CMSG_TYPE_MAP_xxx add, delete, lookup, getnext, getfirst */
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t tid;
			uint32_t count;
			uint32_t flags;					/* 0 if any (add if not existed), 1 is update only */
			uint32_t key[CMSG_MAP_KEY_VALUE_LW];
			uint32_t value[CMSG_MAP_KEY_VALUE_LW];
		};
		uint32_t __raw[353];				/* 4 - 353 LW */
	};
};
struct cmsg_reply_map_op {
	union {
		struct {
			uint32_t type:8;
			uint32_t ver:8;
			uint32_t tag:16;
			uint32_t rc;					/* rc cummulative */
			uint32_t count;					/* # of successful ops */
			uint32_t reserve;
			uint32_t key[CMSG_MAP_KEY_VALUE_LW];
			uint32_t value[CMSG_MAP_KEY_VALUE_LW];
		};
		uint32_t __raw[353];				/* 4 - 353 LW */

	};
};
#endif /* __NFP_LANG_ASM */

#endif	/* _MAP_CTL_MSG_TYPES_H_ */
