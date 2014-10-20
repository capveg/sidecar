#ifndef CONTEXT_H
#define CONTEXT_H

#include <pcap.h>
#include <time.h>

#ifdef REENTRANT
#include <pthread.h>
#endif

struct tapcontext;
#include "connections.h"
#include "packet.h"
#include "wc_event.h"
#include "queue.h"
#include "pmdb.h"

// For Connection tracking hash bucket
#define HASHSIZE 65536
// For generic buffers
#define BUFLEN	8192

// Snaplen param for libpcap
#ifndef MYSNAPLEN
// defaults to unbounded
#define MYSNAPLEN 1500
#endif

// default outgoing TTL - should just read, but is a PITA
#ifndef SIDECAR_DEFAULT_TTL
#define SIDECAR_DEFAULT_TTL 64
#endif

#define LOOP_SELECT 	0
#define LOOP_SIGALRM 	1

// Maxmimum Segment Lifetime == 1 minute
#ifndef MSL_TIME
#define MSL_TIME  (60*1000000)
#endif

#ifndef PRINT_STATS_INTERVAL
#define PRINT_STATS_INTERVAL (5*1000*1000)
#endif

#ifndef MAX_SIDECAR_TOTAL_MEM_KB
#define MAX_SIDECAR_TOTAL_MEM_KB	(90*1024)
#endif

typedef struct tapcontext 
{
	char * pcapfilter;
	int rawSock;
	unsigned int localIP;
	int argc;
	char ** argv;
	pcap_t * handle;
	struct connection *connections[HASHSIZE];
	struct connection *conhead;
	int nConnections;
	int planetlab;
	struct wc_queue * timers;
	char * dev;
	int shouldStop;
	int needRTTBaseline;
	int nOpenConnections;
	int epermCount;
	int sentCount;
	int sentByteCount;
	int sendBudget;
	int printStatsInterval;
	int maxSidecarTotalMem_kb;
	long bpsRateLimit;
	long budgetDelay;
	long outPacketQMaxLen;
#ifdef REENTRANT
	pthread_t * pcapread;
	pthread_mutex_t *lock;
#endif
	int refcount;
	int ttl;
	queuetype * outPacketQ;
	struct timeval outPacketQEmptyTime,startEmptyTime,endEmptyTime;
	int throttleConnections;
	int nThrottledConnections;
	// callbacks
	void (*debugCallback)(char *);
	void (*connectionCallback)(struct connection *);
	void (*initCallback)(void *);
	void *initCBarg;
	pmdb * ipcache, *echoidcache;
} tapcontext;

tapcontext * defaultContext();
extern tapcontext *SidecarCtx;
#define verifySidecarInit() do{ if(_verifySidecarInit()) return 1;}while(0);
int _verifySidecarInit();
int idle_reschedule(struct connection *con);
int schedule_timewait_close(struct connection * con);



#define SYNSENT         0x01
#define SYNACKSENT      0x02
#define CONNECTED       0x03
#define CLOSED          0x04	// this is also the state if local host initiates close
#define TIMEWAIT	0x05
#define REMOTECLOSE	0x06

#endif 
