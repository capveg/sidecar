#ifndef ARTRAT_H
#define ARTRAT_H

#include <time.h>

#ifndef BUFLEN
#define BUFLEN 4096
#endif

#define PROBE_UNSENT	0x00
#define PROBE_SENT	0x02
#define PROBE_RECV	0x03

typedef struct aprobe
{
	u16 seq;
	int status;
	struct timeval sent, recv;
	char options[IP_MAX_OPTLEN];
} aprobe;

// artrat's per connection state
typedef struct artratcon
{
	long usLastRtt;
	long usBaseRtt;
	long usVJRtt;
	long usVJMdev;
	int ProbeOutstanding;
	int ProbeID;
	int ProbeCount;
	int TimeoutID;
	int TotalProbes;
	int DropCount;
	struct timeval ProbeTimestamp;
	int ICMPTimeoutID;
	aprobe ** icmpprobes;
	u16 icmpIpId;
	int nIcmpProbes;
	int nIcmpProbesOutstanding;
	// stats
	
	int ICMPProbeCount;
	int ICMPTotalProbes;
	int ICMPDropCount;
	u32 ICMPTarget;
	int ICMPTargetValid;
	int nStamps;
	int clockprecision[(IP_MAX_OPTLEN/4)];	// only needs 9 for options: extra 10th for local clock (not used)
	int lastclock[(IP_MAX_OPTLEN/4)];	// only needs 9 for options: extra 10th for local clock (not used)
	int xmin[(IP_MAX_OPTLEN/4)];		// should always be '10'
						// this is 11 timestamps = 10 deltas
						// 9 timestamps from ip options and 2 from sent and recv time
	int xminNeedInit;
} artratcon;

extern int CompareType;

#endif
