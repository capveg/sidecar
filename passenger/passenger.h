#ifndef PASSENGER_H
#define PASSENGER_H

#include "sidecar.h"
#include "utils.h"

#ifndef BUFLEN
#define BUFLEN 4096
#endif

typedef struct probe{
	int matched;
	struct timeval sendTime;
	int status;
	int timerID;
	int iteration;
	int probe_num;
	int rpt;
	int ttl;
	int type;
	u32 ip;
	int nRR;
	u32 rr[9];		// yes, we are hard coding 9 b/c 
				// I'll be a monkey's uncle before this const changes
} probe;

#define PROBE_STATUS_UNSENT	0x00
#define PROBE_STATUS_SENT	0x01
#define PROBE_STATUS_TIMEDOUT	0x02
#define PROBE_STATUS_RECEIVED	0x03


#define DEBUG2STDERR 	128

#define SYNACK_PROBE 	0x01
#define FINACK_PROBE	0x02
#define DATA_PROBE 	0x03

#define PHASE_WAITING	0x00
#define PHASE_RPT	0x01
#define PHASE_TR	0x02

#define PROBE_MARCO 	0x00
#define PROBE_PAYLOAD	0x01
#define PROBE_POLLO	0x02
#define PROBE_TR	0x03

#ifndef PASSENGER_OUTDIR
#define PASSENGER_OUTDIR "passenger.r"SIDECAR_VERSION
#endif

#ifndef OUTFILEBUFSIZE
#define OUTFILEBUFSIZE	4096
#endif

#ifndef MAX_REDUNDANT_PROBES
#define MAX_REDUNDANT_PROBES	2
#endif

extern char * ProbeString[];

typedef struct trdata{
	int done;
	int forceCloseID;
	struct timeval starttime;
	int conId;
	int nextTTL;
	struct connection * con;
	int iteration;
	int probeType;
	FILE * out;
	probe ** probes;
	int *nProbes;
	int *nProbesOutstanding;
	int phase;
	int safeTTL;
	struct packet * lastDataPacket;
	char outFileBuf[OUTFILEBUFSIZE];
	u16 nextProbeId;
	int highestReturnedTTL;
	int redundant;
	int hitEndhost;
} trdata;

// globals
extern int MaxTTL;
extern int MSS;		// MTU=1500-ip (20) - tcp(20)-tcp options(12)=1448
extern int Iterations;
extern int UseRR;
extern long int IdleTime;	// just something small
extern long int MAXRTO;	// don't wait longer than 1s, no matter what TCP tells us
extern int DepthFirst;		// foreach ttl { foreach count { send probe}} or the other way?
extern int RPT_payload;
extern int SafeDistance;
extern int MaxSafeTTL;
extern int ForceCloseTimeout;
extern int SkipFinAck;
extern int UseLightTrain;

// protos
void print_ip_options(char *options, int len,probe *, FILE *out);
trdata * trdata_create(struct connection *);
void trdata_free(trdata *);
void trdata_initProbes(trdata *);
void do_finished(struct connection *con, struct trdata *tr);
int vnet_test();


int guess_safe_ttl(struct connection *);

#endif
