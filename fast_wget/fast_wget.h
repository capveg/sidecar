#ifndef WARHEAD_H
#define WARHEAD_H

#include <pthread.h>

#ifndef BUFLEN
#define BUFLEN 8192
#endif

#ifndef DEFAULT_TIMEOUT
// is milliseconds
#define DEFAULT_TIMEOUT	5000
#endif

struct context;

#define MODE_GRAB	0x00
#define MODE_RESOLV	0x01

#define PROTO_WWW	0x00
#define PROTO_BT	0x01

#include "sidecar.h"
#include "targets.h"
#include "grabber.h"

typedef struct context 
{
	int mode;
	int protocol;
	// re: Targets
	struct target **targets;
	int nTargets, nTargetsDone;
	char * targetsFile;
	pthread_mutex_t * targetsLock;
	pthread_mutex_t isDone;
	pthread_cond_t isDoneCond;
	// re: Threads
	int nGrabbers;
	struct grabber_context **grabbers;
	// parameters
	int MaxTTL;
	int MSS;      
	int Planetlab;
	int Iterations;
	int DebugLevel;
	char *OutDir;
	char * EthDev;
	int Port;
	long int IdleTime;      // should be at least 2 time slices to avoid application delay
	long int MAXRTO;        // don't wait longer than .5s, no matter what TCP tells us
	int DepthFirst;		// foreach ttl { foreach count { send probe}} or the other way?
	int connectTimeout;
	int writeTimeout;
	int recurse;
	int mswaitTime;
	int alarmTime;
	int errCount;
	int verbose;
} context;

context * context_create_default();
void print_ip_options(char *options, int optlen, FILE * out);



#endif
