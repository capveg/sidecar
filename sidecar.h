/***************************************************************
 * sidecar.h:
 * 	this file is mean to be sourced into sidecar.i, so 
 * 	only add things here that are to be exported to the higher level scripting lang
 */

#ifndef SIDECAR_H
#define SIDECAR_H
#include <pcap.h>

#ifdef __LCLINT__
#define __BYTE_ORDER __LITTLE_ENDIAN
#endif

#include "version.h"

#ifndef MIN
#define MIN(x,y) ((x)>(y)?(y):(x))
#endif
#ifndef MAX
#define MAX(x,y) ((x)>(y)?(x):(y))
#endif

/* nspring: unsigned long is not enough. */
#ifdef NSPRING_SUCKS
typedef u_int8_t u8;
typedef u_int16_t u16;
typedef u_int32_t u32;
#else
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned long u32;
#endif



struct packet;
struct connection;
struct iphdr;
struct tcphdr;
struct icmp_header;
struct mpls_header;

typedef void (*connectionCallback)(struct connection *);
typedef void (*timerCallback)(struct connection *,void *);
typedef void (*packetCallback)(struct connection *, struct packet *, const struct pcap_pkthdr *);

/*****
 * main sidecar functions
 *****/
int sc_setlogflags(int flags);
int sc_init(char *pcapfilter,char * dev,int planetlab);
int sc_set_max_mem(int kbytes);
int sc_do_loop();
#define sidecarlog(level ,format...) _sidecarlog(level,__FILE__,__LINE__,format)
int _sidecarlog(int level, char *file, int lineno,char * format,...);


/*****
 * register callback functions
 *****/
int sc_register_connect(connectionCallback connectCB);
int sc_register_close(connectionCallback closeCB,struct connection *);
int sc_register_init(void (*initCB)(void *), void *);
int sc_register_timewait(connectionCallback timewaitCB,struct connection *);
int sc_register_idle(connectionCallback idleCB,struct connection *,long uswait);
int sc_register_timer(timerCallback timerCB,struct connection *,long uswait, void *arg);
int sc_cancel_timer(struct connection *,int id);
int sc_register_icmp_in_handler(packetCallback icmp,struct connection * );
int sc_register_icmp_out_handler(packetCallback icmp,struct connection * );
int sc_register_in_handler( packetCallback in, struct connection * );
int sc_register_out_handler( packetCallback out, struct connection * );



/******
 * connection related functions
 ******/
int connection_get_id(struct connection*);
int connection_get_name(struct connection*, char * name, int * namelen);
unsigned int connection_get_remote_ip(struct connection *);
void * connection_set_app_data(struct connection *,void *data );
void * connection_get_app_data(struct connection *);
short connection_get_remote_port(struct connection *);
int connection_get_rtt_estimate(struct connection*, long * avg, long *mdev, long * count);
struct packet * connection_make_packet(struct connection *);
int connection_get_remote_ttl(struct connection *);
int connection_count_old_data(struct connection *);
void connection_force_close(struct connection *);
u16 connection_get_ip_id(struct connection * con);




/*****
 * packet related functions
 *****/
struct packet * packet_create();
int packet_free(struct packet *);
struct packet * packet_duplicate(const struct packet *);
int packet_set_ip_header(struct packet *, struct iphdr *);
int packet_get_ip_header(const struct packet *, struct iphdr *);
int packet_set_icmp_header(struct packet *, struct icmp_header *);
int packet_get_icmp_header(struct packet *, struct icmp_header *);
int packet_set_tcp_header(struct packet *, struct tcphdr *);
int packet_get_tcp_options(struct packet *, char *, int * len);
int packet_set_tcp_options(struct packet *, char *, int len);
int packet_get_tcp_header(struct packet *, struct tcphdr *);
int packet_set_ip_options(struct packet *, char *options, int optlen);
int packet_get_ip_options(struct packet *, char *options, int *optlen);
int packet_set_data(struct packet*, char * data, int datalen);
int packet_get_data(const struct packet*, char * data, int *datalen);
int packet_get_mpls(const struct packet*, struct mpls_header *);
int packet_fill_old_data(struct connection *,struct packet *, int datalen);
struct packet * packet_make_from_buf(struct iphdr *, int caplen);
int packet_send(struct packet *);
int packet_send_train(struct packet **, int nPackets);
int packet_is_dupack(struct packet *, struct connection *);
int packet_is_redundant_ack(struct packet *, struct connection *);
int packet_tag_icmp_ping_with_connection(struct packet *, struct connection *);

/****
 * probe marking functions
 ****/

int probe_add(struct connection *, u16 probe_id, const void * data);
const void * probe_lookup(struct connection *, u16 probe_id);
const void * probe_delete(struct connection *, u16 probe_id);
void probe_cache_flush(struct connection *);

/****
 * utility functions (shouldn't be here, but are nice)
 ****/
struct timeval diff_time(struct timeval now,struct timeval then);


/****
 * constants
 ****/
			// for sc_setlogflags()
#define LOGCRIT         0x01
#define LOGINFO         0x02
#define LOGDEBUG        0x04
#define LOGDEBUG2       0x08
#define LOGDEBUG_TS     0x10
#define LOGDEBUG_RATE   0x20
#define LOGDEBUG_MPLS	0x40
#define LOGAPP		0x80


/****
 * structures
 ****/

#ifndef __BYTE_ORDER
# error "Must include <features.h> or define __BYTE_ORDER"
#endif

// stolen from linux <netinet/ip.h>
#ifndef __NETINET_IP_H
struct iphdr
{
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int ihl:4;
	unsigned int version:4;
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int version:4;
	unsigned int ihl:4;
#else
# error "Please fix <bits/endian.h>"
#endif
	u_int8_t tos;
	u_int16_t tot_len;
	u_int16_t id;
	u_int16_t frag_off;
	u_int8_t ttl;
	u_int8_t protocol;
	u_int16_t check;
	u_int32_t saddr;
	u_int32_t daddr;
	/*The options start here. */
};
#endif	// _NETINET_IP_H
// stolen from linux <netinet/tcp.h>
#ifndef _NETINET_TCP_H
struct tcphdr
{
	u_int16_t source;
	u_int16_t dest;
	u_int32_t seq;
	u_int32_t ack_seq;
#  if __BYTE_ORDER == __LITTLE_ENDIAN
	u_int16_t res1:4;
	u_int16_t doff:4;
	u_int16_t fin:1;
	u_int16_t syn:1;
	u_int16_t rst:1;
	u_int16_t psh:1;
	u_int16_t ack:1;
	u_int16_t urg:1;
	u_int16_t res2:2;
#  elif __BYTE_ORDER == __BIG_ENDIAN
	u_int16_t doff:4;
	u_int16_t res1:4;
	u_int16_t res2:2;
	u_int16_t urg:1;
	u_int16_t ack:1;
	u_int16_t psh:1;
	u_int16_t rst:1;
	u_int16_t syn:1;
	u_int16_t fin:1;
#  else
#   error "Adjust your <bits/endian.h> defines"
#  endif
	u_int16_t window;
	u_int16_t check;
	u_int16_t urg_ptr;
};
#endif // _NETINET_TCP_H


/*
 * ICMP extensions, object header
 */

struct mpls_header {
#if BYTE_ORDER == BIG_ENDIAN
	u_int32_t label:20;
	u_char  exp:3;
	u_char  s:1;
	u_char  ttl:8;
#else
	u_char  ttl:8;
	u_char  s:1;
	u_char  exp:3;
	u_int32_t label:20;
#endif
};




struct icmp_header
{
	u_int8_t type;                /* message type */
	u_int8_t code;                /* type sub-code */
	u_int16_t checksum;
	union
	{
		struct
		{
			u_int16_t id;
			u_int16_t sequence;
		} echo;                     /* echo datagram */
		u_int32_t   gateway;        /* gateway address */
		struct
		{
			u_int16_t __unused;
			u_int16_t mtu;
		} frag;                     /* path mtu discovery */
		struct 
		{
			u_int8_t pointer;
			u_int8_t _unused1;
			u_int16_t __unused;
		} paramprob;
	} un;
};

/* List of standard ICMP types */
#define ICMP_ECHOREPLY          0       /* Echo Reply                   */
#define ICMP_DEST_UNREACH       3       /* Destination Unreachable      */
#define ICMP_SOURCE_QUENCH      4       /* Source Quench                */
#define ICMP_REDIRECT           5       /* Redirect (change route)      */
#define ICMP_ECHO               8       /* Echo Request                 */
#define ICMP_TIME_EXCEEDED      11      /* Time Exceeded                */
#define ICMP_PARAMETERPROB      12      /* Parameter Problem            */
#define ICMP_TIMESTAMP          13      /* Timestamp Request            */
#define ICMP_TIMESTAMPREPLY     14      /* Timestamp Reply              */
#define ICMP_INFO_REQUEST       15      /* Information Request          */
#define ICMP_INFO_REPLY         16      /* Information Reply            */
#define ICMP_ADDRESS            17      /* Address Mask Request         */
#define ICMP_ADDRESSREPLY       18      /* Address Mask Reply           */
#define NR_ICMP_TYPES           18


/* List of standard IP options */
#define IP_MAX_OPTLEN	40
#define IPOPT_EOL               0               /* end of option list */
#define IPOPT_END               IPOPT_EOL
#define IPOPT_NOP               1               /* no operation */
#define IPOPT_NOOP              IPOPT_NOP
#define IPOPT_RR                7               /* record packet route */
#define IPOPT_TS                68              /* timestamp */
#define IPOPT_TIMESTAMP         IPOPT_TS
#define IPOPT_SECURITY          130             /* provide secret,classified,h,tcc */
#define IPOPT_SEC               IPOPT_SECURITY
#define IPOPT_LSRR              131             /* loose source route */
#define IPOPT_SATID             136             /* satnet id */
#define IPOPT_SID               IPOPT_SATID
#define IPOPT_SSRR              137             /* strict source route */
#define IPOPT_RA                148             /* router alert */

	
#endif
