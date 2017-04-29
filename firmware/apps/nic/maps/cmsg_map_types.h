#ifndef _MAP_CTL_MSG_TYPES_H_
#define _MAP_CTL_MSG_TYPES_H_

#define CMSG_MAP_VERSION	1

#ifndef CMSG_PORT
	#define CMSG_PORT		0xffffffff
#endif 

/*
 * enhancement:  add field length to support variable size
 */

/**
 * Format of the control message in MU
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +---------------+---------------+---------------+---------------+
 *    0  |    padding    |     padding   |   cmsg_type   |    version    | <- General cmsg header
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
 *    1  |    map fd (0 is error)                                        |
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

#define CMSG_TYPE_MAP_START		1
#define CMSG_TYPE_MAP_MAX		6

#define CMSG_TYPE_MAX (CMSG_TYPE_LAST_UNUSED)

#define CMSG_TYPE_MAP_ALLOC_REPLY		0x81
#define CMSG_TYPE_MAP_FREE_REPLY		0x82
#define CMSG_TYPE_MAP_LOOKUP_REPLY		0x83
#define CMSG_TYPE_MAP_ADD_REPLY			0x84
#define CMSG_TYPE_MAP_DELETE_REPLY		0x85
#define CMSG_TYPE_MAP_GETNEXT_REPLY		0x86

#define CMSG_TYPE_MAP_REPLY_BIT			7

#define CMSG_MAP_ALLOC_REQ_KEY_IDX		0
#define CMSG_MAP_ALLOC_REQ_VALUE_IDX	1
#define CMSG_MAP_ALLOC_REQ_MAX_IDX		2
#define CMSG_MAP_ALLOC_REQ_FLGS_IDX		3

#define CMSG_MAP_KEY_LW					 10
#define CMSG_MAP_VALUE_LW				  6

#define CMSG_RC_SUCCESS				0
#define CMSG_RC_ERR_MAP_FD			1
#define CMSG_RC_ERR_MAP_NOENT		2
#define CMSG_RC_ERR_MAP_ERR			3
#define CMSG_RC_ERR_MAP_PARSE		4

#ifndef __NFP_LANG_ASM
struct cmsg_req_map_alloc_tbl {
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;
			uint32_t ver:8; 
			uint32_t key_size;		/* in bytes */
			uint32_t value_size;	/* in bytes */
			uint32_t max_entries;
			uint32_t map_flags;		/* not used */
		};
		uint32_t __raw[5];
	};
};
struct cmsg_reply_map_alloc_tbl {
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;
			uint32_t ver:8; 
			uint32_t tid;		/* 0 if error */
		};
		uint32_t __raw[2];
	};
};
struct cmsg_req_map_free_tbl {
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;
			uint32_t ver:8; 
			uint32_t tid;
		};
		uint32_t __raw[2];
	};
};
struct cmsg_reply_map_free_tbl {	
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;
			uint32_t ver:8; 
			uint32_t rc;		/* 0 success */
		};
		uint32_t __raw[2];
	};
};
struct cmsg_req_map_op {
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;		/* CMSG_TYPE_MAP_xxx add, delete, lookup, getnext */
			uint32_t ver:8;
			uint32_t tid;
			uint32_t key[CMSG_MAP_KEY_LW];
			uint32_t value[CMSG_MAP_VALUE_LW];
		};
		uint32_t __raw[18];
	};
};
struct cmsg_reply_map_op {
	union {
		struct {
			uint32_t unused:16;
			uint32_t type:8;
			uint32_t ver:8; 
			uint32_t rc;		/* 0 if success */
			uint32_t data[CMSG_MAP_KEY_LW];
		};
		uint32_t __raw[12];
	};
};
#endif /* __NFP_LANG_ASM */

#endif	/* _MAP_CTL_MSG_TYPES_H_ */
