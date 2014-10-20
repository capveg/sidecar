#ifndef PACKET_H
#define PACKET_H


#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/ip_icmp.h>

struct packet;

#define PACKET_MAGIC 0x11febeef
#define ICMP_EXT_OFFSET    8 /* ICMP type, code, checksum, unused */ + \
                         128 /* original datagram */
#define ICMP_EXT_VERSION 2

#include "sidecar.h"
#include "utils.h"
#include "context.h"

typedef struct packet{
	int magic;
	int type;
	int refcount;
	struct iphdr ip;
	char * ip_opts;
	int ip_opt_len;
	struct tcphdr tcp;
	char * tcp_opts;
	int tcp_opt_len;
	struct icmp_header icmp;

	char * data;
	int datalen;
	char * extra;
	int extralen;
	int hasMpls;
	struct mpls_header mpls;
} packet; 

int packet_send_now(struct tapcontext *);

// all the rest of packet functs are defined in sidecar.h

// used to MPLS ICMP extension parsing
struct icmp_ext_cmn_hdr {
#if BYTE_ORDER == BIG_ENDIAN
	u_char   version:4;
	u_char   reserved1:4;
#else
	u_char   reserved1:4;
	u_char   version:4;
#endif
	u_char   reserved2;
	u_short  checksum;
};

/*
 * ICMP extensions, object header
 */
struct icmp_ext_obj_hdr {
	u_short length;
	u_char  class_num;
#define MPLS_STACK_ENTRY_CLASS 1
	u_char  c_type;
#define MPLS_STACK_ENTRY_C_TYPE 1
};



#endif
