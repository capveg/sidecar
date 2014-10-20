#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <netinet/in.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <values.h>

#include "context.h"
#include "measurements.h"
#include "utils.h"
#include "pcapstuff.h"
#include "log.h"
#include "queue.h"
#include "pmdb_ipcache.h"
#include "pmdb_echoidcache.h"


tapcontext * defaultContext();
static void handle_sigusr1(int);

static void schedulePrintStats();
static void printStats(void * reschedule);
static void drop_priviledges();
static void scheduleSendReBudget();

int Foo=0;	// trying to make stoopid swig warnings go away

int SidecarNeedInit=1;
tapcontext *SidecarCtx=NULL;

/********************* local structs
 */
struct event_type
{
	connectionCallback fun;
	timerCallback timerCB;
	void * arg;
	void * arg2;
	int id;
};

/*********************************************************
 * tapcontext * defaultContext();
 * 	return a context filled in with defaults
 */

tapcontext * defaultContext()
{
	SidecarCtx = malloc_and_test(sizeof(tapcontext));
	assert(SidecarCtx);

	SidecarCtx->localIP=getLocalIP();
	memset(SidecarCtx->connections,0,sizeof(connection*)*HASHSIZE);
	SidecarCtx->pcapfilter=NULL;
	SidecarCtx->shouldStop=0;
	SidecarCtx->nConnections=0;
	SidecarCtx->planetlab=0;	// assume we are not on planetlab by default
	SidecarCtx->handle=NULL;
	SidecarCtx->dev=NULL;
	SidecarCtx->conhead=NULL;
	SidecarCtx->timers=NULL;
	SidecarCtx->ttl=SIDECAR_DEFAULT_TTL;
	SidecarCtx->needRTTBaseline=1;
	SidecarCtx->nOpenConnections=0;
	SidecarCtx->epermCount=0;
	SidecarCtx->sentCount=0;
	SidecarCtx->sentByteCount=0;
	SidecarCtx->maxSidecarTotalMem_kb=MAX_SIDECAR_TOTAL_MEM_KB;
	SidecarCtx->sendBudget=0;
	SidecarCtx->throttleConnections=0;
	SidecarCtx->bpsRateLimit=64000;		// 500 kbps = 64000 B/s; planetlab max
	SidecarCtx->budgetDelay=10;			// update the budget every 10ms
	SidecarCtx->outPacketQMaxLen=SidecarCtx->bpsRateLimit/80;	// pick queue size as a 1 sec max delay, assume packetsize=80
	SidecarCtx->nThrottledConnections=0;
#ifdef REENTRANT
	SidecarCtx->lock = (pthread_mutex_t *) malloc_and_test(sizeof(pthread_mutex_t));
	assert(SidecarCtx->lock);
	pthread_mutex_init(SidecarCtx->lock,NULL);
#endif
	SidecarCtx->connectionCallback=NULL;
	SidecarCtx->initCallback=NULL;
	SidecarCtx->initCBarg=NULL;
	SidecarCtx->debugCallback=NULL;
	SidecarCtx->outPacketQ = Q_create();
	SidecarCtx->printStatsInterval = PRINT_STATS_INTERVAL;
	timerclear(&SidecarCtx->outPacketQEmptyTime);
	SidecarCtx->ipcache= pmdb_create(PMDB_IPCACHE_HASHSIZE,pmdb_ipcache_hash,pmdb_ipcache_cmp,NULL);
	assert(SidecarCtx->ipcache);
	SidecarCtx->echoidcache= pmdb_create(PMDB_ECHOIDCACHE_HASHSIZE,pmdb_echoidcache_hash,pmdb_echoidcache_cmp,pmdb_echoidcache_free);
	assert(SidecarCtx->echoidcache);
	return SidecarCtx;
}


/*********************************************************
 * int sc_init(char * pcapfilter,char * dev,int planetlab)
 * 	setup all sorts of local variables 
 * 	pcapfilter is the filter string to listen for
 * 	planetlab is 1 if on planetlab, else 0
 * 	returns 1 on err, 0 on success
 */

int sc_init(char * pcapfilter,char * dev,int planetlab)
{
	int err;
	int flags;
	int opt,optlen;
	struct rlimit rlim;

	// mark all the logging levels to show how much we're logging
	sidecarlog(LOGDEBUG," -- DEBUG logging enabled\n");
	sidecarlog(LOGINFO," -- INFO logging enabled\n");
	sidecarlog(LOGCRIT," -- CRIT logging enabled\n");
	sidecarlog(LOGDEBUG2," -- DEBUG2 logging enabled\n");
	sidecarlog(LOGDEBUG_TS," -- DEBUG_TS logging enabled\n");
	sidecarlog(LOGDEBUG_RATE," -- DEBUG_RATE logging enabled\n");
	sidecarlog(LOGDEBUG_MPLS," -- DEBUG_MPLS logging enabled\n");
	sidecarlog(LOGAPP," -- APP logging enabled\n");
	// init context
	if(SidecarCtx==NULL)
		SidecarCtx=defaultContext();
	SidecarCtx->planetlab=planetlab;
	SidecarCtx->pcapfilter=strdup(pcapfilter);
	if(SidecarCtx->pcapfilter==NULL)
	{
		sidecarlog(LOGCRIT,"sc_init:: need to specify valid filter string: passed '%s'\n",
				pcapfilter?pcapfilter:"(NULL)");
		return 1;
	}
	if(dev)
		SidecarCtx->dev=strdup(dev);
	err=pcap_init(SidecarCtx);
	if(err)
		return err;

	SidecarCtx->rawSock = socket(PF_INET,SOCK_RAW,IPPROTO_TCP);
	if(SidecarCtx->rawSock < 0 )
	{
		sidecarlog(LOGCRIT,"sc_init::socket(PF_INET,SOCK_RAW,IPPROTO_TCP) : %s\n",strerror(errno));
		return(1);
	}
	// init timer mechanism
	SidecarCtx->timers = wc_queue_init(10);
	assert(SidecarCtx->timers);

	// set IP_HDRINCL:
	opt=1;
	optlen=sizeof(opt);
	err = setsockopt(SidecarCtx->rawSock,SOL_IP,IP_HDRINCL,&opt,optlen);
	if(err)
	{
		sidecarlog(LOGCRIT,"sc_init::setsockopt:IP_HDRINCL: %s\n",strerror(errno));
		return(1);
	}
	// set non-blocking
	flags = fcntl(SidecarCtx->rawSock,F_GETFL);
	assert(flags!=-1);
	flags|=O_NONBLOCK;
	err = fcntl(SidecarCtx->rawSock,F_SETFL,flags);
	if(err)
	{
		sidecarlog(LOGCRIT,"sc_init::fcntl(rawSock,O_NONBLOCK): %s\n",strerror(errno));
		return(1);
	}
	// try to drop priviledges
	drop_priviledges();		// comment out for debugging
	// make sure we can dump core if we have to
	rlim.rlim_cur=MAXINT;
	rlim.rlim_max=MAXINT;
	err=setrlimit(RLIMIT_CORE,&rlim);
	if(err)
		sidecarlog(LOGCRIT,"sc_init::setrlimit(RLIMIT_CORE): grr!: %s\n", strerror(errno));
	signal(SIGUSR1,handle_sigusr1);
	schedulePrintStats();
	scheduleSendReBudget();
	SidecarNeedInit=0;	// mark init as done
	return 0;	// Success
}

/**********************************************************
 * int verifySidecarInit();
 * 	run in every non-init call to make sure that init has been called
 * 	if not, then log error, and return 1
 */

// #define verifySidecarInit() do{ if(_verifySidecarInit()) return -1;}while(0);
int _verifySidecarInit()
{
	if(SidecarNeedInit==0)
		return 0;
	// have not been init'ed
	sidecarlog(LOGCRIT," tried to use library call without first calling init\n");
	return 1;
}
/***********************************************************************************
 * int sc_set_max_mem(int kbytes)
 * 	change the default maximum amount of memory used by Sidecar; 
 * 	return old value
 */

int sc_set_max_mem(int kbytes)
{
	int old; 

	verifySidecarInit();
	old= SidecarCtx->maxSidecarTotalMem_kb;
	SidecarCtx->maxSidecarTotalMem_kb=kbytes;
	return old;
}

/**************************************************************
 * int sc_register_init(void (*initCB)(void *), void *);
 * 	register a callback to run after initialization
 */

int sc_register_init(void (*initCB)(void *), void *arg)
{
	verifySidecarInit();
	SidecarCtx->initCallback=initCB;
	SidecarCtx->initCBarg=arg;
	return 0;
}


/*************************************************************
 * int sc_register_debug(int (*debug)(char *));
 * 	register a callback for the (testing) debug call back
 */
int sc_register_debug(void (*debug)(char *))
{
	verifySidecarInit();
	SidecarCtx->debugCallback=debug;

	// make_script_call(debug,args)
	// not impled'swig_call("function_symbol",int foo);
	SidecarCtx->debugCallback("testing... 1.2.3\n");
	return 0;
}

/***********************************************************************
 * int sc_register_connect(void (*connectCB)(struct connection *));
 * 	register a callback for new connections
 */

int sc_register_connect(void (*connectCB)(struct connection *))
{
	verifySidecarInit();
	SidecarCtx->connectionCallback=connectCB;
	return 0;
}
/*******************************************************************************
 * static void idle_handler(void * arg)    // local function
 * 	This function gets called when the timer goes off.
 * 	If the connection is idle, then call the idleCallback, 
 * 	else reschedule the timer for IdleTime later
 */
static void idle_handler(void * arg)	// local function
{
	struct event_type *e=(struct event_type *)arg;
	struct connection * con = (struct connection *)e->arg;
	int old;
	struct timeval tv;
	assert(con);
	if(con->state == CLOSED)
	{
		con->idletimerId=-1;
		connection_free(SidecarCtx,con);
		free(e);
		return;	// don't reschedule idle on closed connection
	}
	if(connection_is_idle(con))
	{	// call the callback
		sidecarlog(LOGDEBUG," idle timer %d expired on connection %d: calling idle callback\n",
				con->idletimerId,con->id);
		e->fun(con);
		con->idletimerId=-1;		// erase old idletimer ID
		sidecarlog(LOGDEBUG," connection %d return from idle callback\n", con->id);
		connection_free(SidecarCtx,con);
		free(e);
		return;
	}
	// connection not idle, reschedule
	gettimeofday(&tv,NULL);
	tv.tv_sec += con->idletimeout/1000000;
	tv.tv_usec += con->idletimeout%1000000;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	old = con->idletimerId;
	con->idletimerId=wc_event_add(SidecarCtx->timers,idle_handler,arg,tv);		// keep the same event_type args
	e->id=con->idletimerId;
	sidecarlog(LOGDEBUG," Rescheduling idler timer event for connection %d from id %d to %d to %ld.%.6ld\n",
			con->id , old, con->idletimerId,tv.tv_sec,tv.tv_usec);
	return;
}

/************************************************************************
 * int sc_register_idle(void (*idleCB)(struct connection *),long uswait);
 * 	register a callback for when the connection goes idle
 * 	'uswait' specifies how long the connection should be idle for, in microseconds
 * 
 * 	a call with idleCB==NULL just cancels any existing idle timer
 */

int sc_register_idle(void (*idleCB)(struct connection *),struct connection * con,long uswait)
{
	struct timeval tv;
	struct event_type * e;
	void (*fun)(void *);
	void * arg;
	int err;
	verifySidecarInit();
	
	// are we just deleting existing timer?
	if(idleCB ==NULL)
	{
		if(con->idletimerId==-1)	// nothing to delete
			return -1;
		err=wc_event_remove(SidecarCtx->timers,con->idletimerId,&fun,&arg);
		assert(err==0);
		free((struct event_type*)arg);
		con->idletimerId=-1;
		connection_free(SidecarCtx,con);// release this ref count on the connection, 
						// potentially freeing it
		return 0;
	}
	if(con->idletimerId!=-1)
	{
		err=wc_event_remove(SidecarCtx->timers,con->idletimerId,&fun,&arg);
		assert(err==0);
		e= (struct event_type*)arg;		// reuse old event memory
	} 
	else 
	{
		connection_inc_ref(con);		// only inc the ref if we are a new timer
		e = malloc_and_test(sizeof(struct event_type));
		assert(e);
	}
	gettimeofday(&tv,NULL);
	tv.tv_sec += uswait/1000000;
	tv.tv_usec += uswait%1000000;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	e->fun=idleCB;
	e->arg = con;
	con->idletimerId= wc_event_add(SidecarCtx->timers,idle_handler,e, tv);
	e->id=con->idletimerId;
	con->idletimeout=uswait;
	sidecarlog(LOGDEBUG," Scheduling idle timer %d for %ld us\n",con->idletimerId,uswait);
	return con->idletimerId;
}

/************************************************************************
 * int sc_register_timer(void (*timerCB)(struct connection *),long uswait);
 * 	register a callback that should be called every 'uswait' microseconds
 */
static void timer_handler(void * event_arg)
{
	struct event_type *e=(struct event_type *)event_arg;
	struct connection * con = (struct connection *)e->arg;
	sidecarlog(LOGDEBUG," timer %d expired on connection %d: calling timer callback\n",
			e->id,con->id);
	if(con->state!=CLOSED)		// don't call on closed conncection
		e->timerCB(con,e->arg2);
	sidecarlog(LOGDEBUG," connection %d return from timer callback\n", con->id);
	connection_free(SidecarCtx,con);
	free(e);
}

int sc_register_timer(void (*timerCB)(struct connection *,void * ),struct connection * con,long uswait, void * arg2)
{
	struct timeval tv;
	struct event_type * e;
	int id;
	verifySidecarInit();
	
	e = malloc_and_test(sizeof(struct event_type));
	assert(e);
	gettimeofday(&tv,NULL);
	tv.tv_sec += uswait/1000000;
	tv.tv_usec += uswait%1000000;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	e->timerCB=timerCB;
	e->arg = con;
	e->arg2 = arg2;
	connection_inc_ref(con);
	id= wc_event_add(SidecarCtx->timers,timer_handler,e, tv);
	e->id=id;
	sidecarlog(LOGDEBUG," Scheduling timer %d for %ld us (%ld.%.6ld\n",
			id,uswait,(long)tv.tv_sec,(long)tv.tv_usec);
	return id;
}


/***************************************************************************
 * int sc_cancel_timer(struct connection *,int id);
 * 	cancel a timer, by id
 */
int sc_cancel_timer(struct connection *con,int id)
{
	struct event_type *e;
	void (*fun)(void *);
	void *arg;
	int err;

	if(id<0)
	{
		// this used to be an abort(), but it is too easy for the driver
		// to accidentally call this on a -1 id, so changed to a non-fatal error
		sidecarlog(LOGCRIT," Ignoring bogus request to cancel timer id %d\n",id);
		return 0;
	}
	sidecarlog(LOGDEBUG," Canceling timer %d\n",id);
	err = wc_event_remove(SidecarCtx->timers,id,&fun,&arg);
	if(err!=0)		// did we find something to delete?
	{
		sidecarlog(LOGINFO," tried to delete non-existant timer id %d\n",id);
		return err;	// okay if no, could be the timer already went off
	}
	e = (struct event_type *) arg;
	assert(e->id == id);			// make sure we got what we asked for
	connection_free(SidecarCtx,(connection *)e->arg);	// this is kosher, b/c only the
							// higher level app calls this
							// even though they maintain a ptr to
							// con, this will never actually free
							// the data, b/c the app is never called
							// when the connection is closed
	free(e);
	return err;
}



/************************************************************************
 * int sc_register_icmp_handler(void (*handler)(struct connection *, struct packet *));
 * 	register a callback that should be called everytime we receive a measurement
 * 	packet
 */

int sc_register_icmp_in_handler(packetCallback icmp, struct connection * con)
{
	verifySidecarInit();
	con->icmpInCallback=icmp;
	return 0;
}
int sc_register_icmp_out_handler(packetCallback icmp, struct connection * con)
{
	verifySidecarInit();
	con->icmpOutCallback=icmp;
	return 0;
}
/************************************************************************
 * int sc_register_in_handler(void (*handler)(struct connection *, struct packet *));
 * 	register a callback that should be called everytime we receive a data
 * 	packet
 */

int sc_register_in_handler(packetCallback in, struct connection * con)
{
	verifySidecarInit();
	con->inpacketsCallback=in;
	return 0;
}

/************************************************************************
 * int sc_register_out_handler(void (*handler)(struct connection *, struct packet *));
 * 	register a callback that should be called everytime we send a data
 * 	packet
 */

int sc_register_out_handler(packetCallback out, struct connection * con)
{
	verifySidecarInit();
	con->outpacketsCallback=out;
	return 0;
}

/************************************************************************
 * int sc_register_close(void (*closeCB)(struct connection *));
 * 	register to callback that is called when a connection is closed
 */
int sc_register_close(void (*closeCB)(struct connection *),struct connection * con)
{
	verifySidecarInit();
	con->closedconnectionCallback=closeCB;
	return 0;
}


/************************************************************************
 * int sc_register_timewait(void (*timewaitCB)(struct connection *));
 * 	register to callback that is called when a connection goes to timewait state
 */
int sc_register_timewait(void (*timewaitCB)(struct connection *),struct connection * con)
{
	verifySidecarInit();
	con->timewaitCallback=timewaitCB;
	return 0;
}


/**********************************************************************
 * int schedule_timewait_close(struct connection * con)
 * 	schedule a timer on this connection to go from timewait to closed
 * 		-- need to handle all of the connection close stuff here
 */
void timewait_close(void * arg)
{
	struct connection * con=(struct connection *)arg;
	if(con->closedconnectionCallback)
	{
		// ASSUME that con->closedconnectionCallback is set to NULL when the connection is closed
		sidecarlog(LOGDEBUG," timewait_close: calling close Callback on connection %d\n",con->id);
		con->closedconnectionCallback(con);
		con->closedconnectionCallback=NULL;		// don't close the connection twice
		sidecarlog(LOGDEBUG," timewait_close: returning from close Callback on connection %d\n",con->id);
		con->state=CLOSED;
		connection_free(SidecarCtx,con);	// once for connection, if not closed
	}
	connection_free(SidecarCtx,con);	// once for timer inc
}

int schedule_timewait_close(struct connection * con)
{
	struct timeval tv;
	int id;
	assert(con);
	assert(con->magic==CONMAGIC);

	gettimeofday(&tv,NULL);
	tv.tv_sec += MSL_TIME/1000000;
	tv.tv_usec += MSL_TIME%1000000;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	connection_inc_ref(con);
	id= wc_event_add(SidecarCtx->timers,timewait_close,con, tv);
	sidecarlog(LOGDEBUG," Scheduling timewait timer %d for %ld us\n",id,MSL_TIME);
	return id;
}
/*************************************************************************
 * void handle_sigusr1(int);
 * 	set shouldStop to 1 in SidecarCtx
 */

void handle_sigusr1(int ignore)
{
	struct pcap_stat ps;
	SidecarCtx->shouldStop=1;
	pcap_stats(SidecarCtx->handle,&ps);
	sidecarlog(LOGINFO,"Got SIGUSR1 --- exiting\n");
	sidecarlog(LOGINFO,"Pcap Stats: %d packets received -- %d dropped (%f%%)\n",
			ps.ps_recv,ps.ps_drop,100.0*(float)ps.ps_drop/ps.ps_recv);
	fprintf(stderr,"Passenger exiting on sigusr1: %d packets received -- %d dropped (%f%%)\n",
			ps.ps_recv,ps.ps_drop,100.0*(float)ps.ps_drop/ps.ps_recv);
}

/**************************************************************************
 * void schedulePrintStats()
 * 	generate an event s.t. printStats is called ctx->printStatsInterval time from now
 */

void schedulePrintStats()
{
	struct timeval tv;
	int id;
	void *reschedule=NULL;
	gettimeofday(&tv,NULL);
	tv.tv_sec += SidecarCtx->printStatsInterval/1000000;
	tv.tv_usec += SidecarCtx->printStatsInterval%1000000;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	reschedule=schedulePrintStats;	// HACK: just need reschedule to be non-NULL
	id=wc_event_add(SidecarCtx->timers,printStats,reschedule, tv);
	assert(id>=0);
}

/********************************************************************************
 * void printStats(void *reschedule)
 * 	print some stats as LOGINFO, and call schedulePrintStats unless reschedule==NULL
 */

void printStats(void * reschedule)
{
	struct pcap_stat ps;
	static int TotalDrops=0;
	static int TotalEperm=0;
	static int TotalRecv=0;
	static int TotalSent=0;
	static int TotalSentBytes=0;
	static int TotalThrottled=0;
	static struct timeval TotalEmptyTime = {0,0};
	static struct timeval TotalTime = {0,0};
	static struct timeval now = {0,0};
	static struct timeval then = {0,0};
	long totalmem, resmem;
	struct timeval delta,tmp;


	pcap_stats(SidecarCtx->handle,&ps);
	getmemusage(&totalmem,&resmem);
	totalmem/=1024;
	resmem/=1024;


	TotalDrops+=ps.ps_drop;
	TotalEperm+=SidecarCtx->epermCount;
	TotalRecv+=ps.ps_recv;
	TotalSent+=SidecarCtx->sentCount;
	TotalSentBytes+=SidecarCtx->sentByteCount;
	TotalThrottled+=SidecarCtx->nThrottledConnections;
	// time related
	gettimeofday(&now,NULL);
	if(!timerisset(&then))	// if this is our first time calling this
	{
		// then assume that this first call happened printStatsInterval miliseconds ago
		then=now;
		then.tv_sec-=SidecarCtx->printStatsInterval/1000000;
		then.tv_usec-=SidecarCtx->printStatsInterval%1000000;
		if(then.tv_usec<0)
		{
			then.tv_sec--;
			then.tv_usec+=1000000;
		}
	}
	if(timercmp(&SidecarCtx->startEmptyTime,&SidecarCtx->endEmptyTime,>))		// if we are in the middle of the empty time
	{
		timersub(&now,&SidecarCtx->startEmptyTime,&tmp);			// add that time onto counter
		timeradd(&tmp,&SidecarCtx->outPacketQEmptyTime,&SidecarCtx->outPacketQEmptyTime);
		SidecarCtx->startEmptyTime=now;						// and restart
	}
	timersub(&now,&then,&delta);
	timeradd(&TotalEmptyTime,&SidecarCtx->outPacketQEmptyTime,&TotalEmptyTime);	// inc the totalEmpty time
	timeradd(&TotalTime, &delta,&TotalTime);					// inc total time 

	sidecarlog(LOGINFO,"pQ %d mem %ld res %ld KB; nIP %d nC %d nD %d nE %d nR %d nS %d kbS %ld nT %d tE %ld.%.6ld (%6.4f %%)"
			":: totD %d totE %d totR %d totS %d totMBS %ld totT %d totE %ld.%.6ld (%6.4f %%)\n",
			Q_size(SidecarCtx->outPacketQ),
			totalmem,resmem,
			pmdb_count_entries(SidecarCtx->ipcache),
			SidecarCtx->nOpenConnections,
			ps.ps_drop,
			SidecarCtx->epermCount,
			ps.ps_recv,
			SidecarCtx->sentCount,
			SidecarCtx->sentByteCount/1024,
			SidecarCtx->nThrottledConnections,
			SidecarCtx->outPacketQEmptyTime.tv_sec,SidecarCtx->outPacketQEmptyTime.tv_usec,
			100*timerdiv(&SidecarCtx->outPacketQEmptyTime,&delta),
			TotalDrops,TotalEperm,TotalRecv,TotalSent,TotalSentBytes/(1024*1024),TotalThrottled,
			TotalEmptyTime.tv_sec,TotalEmptyTime.tv_usec,
			100*timerdiv(&TotalEmptyTime,&TotalTime));
	// reset all counters for next period
	SidecarCtx->epermCount=0;
	SidecarCtx->sentCount=0;
	SidecarCtx->sentByteCount=0;
	SidecarCtx->nThrottledConnections=0;
	timerclear(&SidecarCtx->outPacketQEmptyTime);
	// test to make sure we aren't too big
	assert((totalmem<SidecarCtx->maxSidecarTotalMem_kb)||(SidecarCtx->maxSidecarTotalMem_kb<1));
	if(reschedule!=NULL)
		schedulePrintStats();
	then=now;
}

/***************************************************************************************
 * static void drop_priviledges();
 * 	try to setuid() to euid if not 0, to $USER if not root, or SUDO_USER if exists, in that order
 */

void drop_priviledges()
{
	uid_t uid;
	gid_t gid;
	char * user;
	struct passwd * pw;
	int err;

	uid=getuid();
	gid=getgid();
	if((uid == 0)||(gid==0))	// we are probably in a sudo_shell
	{
		user = getenv("USER");
		if((!user)||(!strcmp(user,"root")))
		{
			user = getenv("SUDO_USER");
		}
		if(!user)
		{
			sidecarlog(LOGCRIT,"failed to drop priviledges\n");
			return;
		}
		pw = getpwnam(user);
		if(!pw)
		{
			sidecarlog(LOGCRIT,"failed to drop priviledges: getpwnam()\n");
			return;
		}
		uid=pw->pw_uid;
		gid=pw->pw_gid;
		if(uid == 0)
		{
			sidecarlog(LOGCRIT,"failed to drop priviledges: uid still 0()\n");
			return;
		}
	}
	setgid(gid);		// who cares if setgid fails
	err = setuid(uid);
	if(err)
	{
			sidecarlog(LOGCRIT,"failed to drop priviledges: setuid(): %s\n",strerror(errno));
	}
	else
	{
			sidecarlog(LOGINFO,"dropped priviledges to uid %d gid %d\n",uid,gid);
	}
}
/*************************************************************************************************
 * void sendReBudget(void * ignore)
 * 	add the right amount of budget tokens to SidecarCtx->sendBudget
 * 	to enforce rate limiting
 */

static void sendReBudget(void * ignore)
{
	long inc = SidecarCtx->bpsRateLimit*SidecarCtx->budgetDelay/1000;
	assert(inc>0);
	SidecarCtx->sendBudget= inc;
	sidecarlog(LOGDEBUG_RATE,"sendReBudget: value %ld \n",SidecarCtx->sendBudget);
	scheduleSendReBudget();
}

/*************************************************************************************************
 * void scheduleSendReBudget();
 *     schedule sendReBudget SidecarCtx->budgetDelay time from now
 */

static void scheduleSendReBudget()
{
	struct timeval tv;
	int id;
	gettimeofday(&tv,NULL);
	tv.tv_usec += 1000*SidecarCtx->budgetDelay;
	if(tv.tv_usec>1000000)
	{
		tv.tv_usec-=1000000;
		tv.tv_sec++;
	}
	sidecarlog(LOGDEBUG_RATE,"scheduling SendReBudget for %ld.%.6ld\n",tv.tv_sec,tv.tv_usec);
	id=wc_event_add(SidecarCtx->timers,sendReBudget,NULL, tv);
	assert(id>=0);
}



