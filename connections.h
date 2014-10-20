#ifndef CONNECTIONS_H
#define CONNECTIONS_H

#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <time.h>

struct connection;
#include "sidecar.h"
#include "context.h"
#include "packet.h"

#ifndef CONNECTION_DEFAULT_OLD_DATA
	// keep 2 full packets, by default
#define CONNECTION_DEFAULT_OLD_DATA 3000
#endif

#define CONMAGIC 0xdeadbeef
#define CON_MAGIC_STR "SIDECAR"

#define NPROBES 256

typedef struct probedata {
	const void * data;
	u16 id;
	struct probedata * next;
} probedata;


struct timestamp_bucket;

typedef struct connection
{
	int magic;
	unsigned int remoteIP;
	u16 rport,lport;
	struct connection * next;		// for hash collisions
	struct connection * connext;		// for iterating through connections
	struct connection * conprev;		// for iterating through connections
	unsigned int lSeq,rSeq;
	unsigned int ackrecved;
	int lWindow,rWindow;
	u16 l_ip_id;
	int state;
	int idletimerId;
	long idletimeout;
	void * appData;				// place for higher level app to store per connection data
	int remoteTTL;
#ifdef REENTRANT
	pthread_mutex_t *lock;
#endif
	int refcount;
	int id;
	char * oldData;
	int oldDataIndex;
	int oldDataMax;
	int oldDataFull;
	struct timestamp_bucket * tsb_head, * tsb_tail;
	u32 mostRecentTimestamp;
	long rtt, mdevrtt, rtt_estimates;
	probedata * probeTracking[NPROBES];

	packetCallback inpacketsCallback;
	packetCallback outpacketsCallback;
	packetCallback icmpOutCallback;
	packetCallback icmpInCallback;
	void (*timewaitCallback)(struct connection *);
	void (*closedconnectionCallback)(struct connection *);
} connection;

typedef struct iphdr iphdr;
typedef struct tcphdr tcphdr;

connection * connection_lookup(struct tapcontext *, iphdr *ip, tcphdr *tcp);
// given an ICMP packet, figure out what connection it was destined for
connection * connection_lookup_by_icmp(struct tapcontext *, iphdr *ip, int len);
connection * connection_create(struct tapcontext *, iphdr *ip, tcphdr *tcp);
int connection_update(struct tapcontext *, connection *, iphdr *ip,tcphdr * tcp);
int connection_free(struct tapcontext *, connection *);
int connection_inc_ref(struct connection * con);
int connection_process_out_timestamp(struct connection *con, u32 value, struct timeval now);
int connection_process_in_timestamp(struct connection *con, u32 echo, struct timeval now);
int connection_is_idle(struct connection *);
int mkhash(unsigned int ip, unsigned short port);


extern char * connection_statestr[];

#endif
