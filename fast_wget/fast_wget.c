/**************************************************************************************
 * 	'Warhead' is the driver module for sidecar
 * 		- Snow Crash ref
 * 	Scratch that -- 'warhead' is a horrible name; changed to descriptive 'fast_wget'
 * 		
 * Goal: 
 *	Multi-threaded wget so that passenger can traverse many websites
 *			- capveg '06
 */



#include <assert.h>
#include <netinet/ip.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <sys/types.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>


// for inet_ntop
#include <sys/socket.h>
#include <arpa/inet.h>


#include "sidecar.h"
#include "fast_wget.h"


static void usage(char *,char*);
static int parse_args(context *,int argc, char *argv[]);
static void handle_alarm(int );
context *Ctx;



/***********************************************************************
 * int main(int argc, char * argv[])
 * 	parse some args, register some callbacks, and call sc_main_loop()
 */

int main(int argc, char * argv[])
{
	int i;
	struct rlimit lims;
	void *ignore;

	Ctx = context_create_default();
	parse_args(Ctx,argc,argv);
	targets_read(Ctx);
	target_randomize(Ctx);

	// set the stack size small, so we don't take up lots of stack space
	memset(&lims,0,sizeof(lims));
	lims.rlim_cur = lims.rlim_cur = 1024;		// set to 1k
	setrlimit(RLIMIT_STACK,&lims);


	pthread_mutex_lock(Ctx->targetsLock);	// targets start off as locked, to stop threads
						// from going while we are still setting up

	// create the set of grabber threads
	Ctx->grabbers=malloc(sizeof(grabber_context *)*Ctx->nGrabbers);
	assert(Ctx->grabbers);
	memset(Ctx->grabbers,0,sizeof(grabber_context *)*Ctx->nGrabbers);
	for(i=0;i<Ctx->nGrabbers;i++)
	       Ctx->grabbers[i]=grabber_create(Ctx,i);	

	signal(SIGALRM,handle_alarm);
	alarm(Ctx->alarmTime);
	pthread_mutex_unlock(Ctx->targetsLock);		// let the grabber threads start
	for(i=0;i<Ctx->nGrabbers;i++)
		pthread_join(*Ctx->grabbers[i]->thread,&ignore);// wait for threads to signal doneness
	for(i=0;i<Ctx->nGrabbers;i++)
		grabber_free(Ctx->grabbers[i]);
	return 0;				
}
/*****************************************************************************
 * context * context_create_default()
 * 	create a set of defaults and return them
 */
context * context_create_default()
{
	context * ctx;
	ctx = malloc(sizeof(context));
	assert(ctx);

	ctx->mode=MODE_GRAB;
	ctx->targetsLock=malloc(sizeof(pthread_mutex_t));
	assert(ctx->targetsLock);
	pthread_mutex_init(ctx->targetsLock,NULL);	// FAST lock should be okay `man 3 pthread_mutexattr_init`
	ctx->targetsFile="urls.good";
	ctx->targets=NULL;

	// globals
	ctx->MaxTTL=30;
	ctx->protocol=PROTO_WWW;
	ctx->MSS=1448;		// MTU=1500-ip (20) - tcp(20)-tcp options(12)=1448
	ctx->Planetlab=0;
	ctx->Iterations=3;
	ctx->DebugLevel=LOGINFO|LOGCRIT;
	ctx->OutDir="outdir.r"SIDECAR_VERSION;
	ctx->EthDev=NULL;
	ctx->IdleTime=20000;	// should be at least 2 time slices to avoid application delay
	ctx->MAXRTO=500000;		// don't wait longer than .5s, no matter what TCP tells us
	ctx->DepthFirst=0;		// foreach ttl { foreach count { send probe}} or the other way?
	ctx->connectTimeout=DEFAULT_TIMEOUT;
	ctx->writeTimeout=DEFAULT_TIMEOUT;
	ctx->nGrabbers=100;
	ctx->recurse=0;
	ctx->mswaitTime=15000;		// default to 15 seconds
	ctx->nTargets=ctx->nTargetsDone=0;
	ctx->alarmTime=5;
	ctx->errCount=0;
	ctx->verbose=0;
	pthread_mutex_init(&ctx->isDone,NULL);
	pthread_cond_init(&ctx->isDoneCond,NULL);
	return ctx;
}

/*********************************************************************************
 * int parse_args(int argc, char *argv[])
 * 	read in command line options,
 * 	call usage() if there are errors
 */

int parse_args(context * ctx,int argc, char *argv[])
{
	int c;
	while((c=getopt(argc,argv,"a:Bc:rn:t:w:v"))!=EOF)
	{
		switch(c)
		{
			case 'a':
				ctx->alarmTime=atol(optarg);
				break;
			case 'B':
				ctx->protocol=PROTO_BT;
				break;
			case 'c':
				ctx->connectTimeout=atol(optarg);
				break;
			case 'n':
				ctx->nGrabbers=atol(optarg);
				break;
			case 'v':
				ctx->verbose=1;
				break;
			case 'r':
				ctx->mode=MODE_RESOLV;
				break;
			case 'w':
				ctx->mswaitTime=atol(optarg);
				break;
			case 't':
				ctx->targetsFile=strdup(optarg);
				break;
			default:
				usage("invalid arg",(char *) &optopt);
		};
	}
	return 0;
}

/*********************************************************************
 * 	void usage(char *s1, char *s2)
 * 		print usage message, then exit()
 */
void usage(char *s1, char *s2)
{
	if(s1)
		fprintf(stderr,"%s",s1);
	if(s2)
		fprintf(stderr," %s",s2);
	if(s1||s2)
		fprintf(stderr,"\n");
	fprintf(stderr,"Usage:\n\n"
			"warhead [options]\n\n"
			"	-v [verbose]			\n"
		"	-a alarmTime			[%d]\n"
		"	-B  -- use the BitTorrent protcol instead of WWW\n"
		"	-c connectTimeout		[%d]\n"
		"	-w mswaittime			[%d]\n"
		"	-n nThreads			[%d]\n"
		"	-r [enable resolve mode]	\n"
		"	-t targetsfile			['%s']\n",
		Ctx->alarmTime,
		Ctx->connectTimeout,
		Ctx->mswaitTime,
		Ctx->nGrabbers,Ctx->targetsFile);
	exit(1);
}
/************************************************************************
 * int handle_alarm(int)
 * 	periodically (every ctx->alarmTime seconds),
 * 		print a progress message
 */

void  handle_alarm(int ignore)
{
	static int old=0;
	time_t now;
	struct tm tm_result;
	char timebuf[BUFLEN];

	// calc time, make it look pretty
	now = time(NULL);
	localtime_r(&now,&tm_result);
	asctime_r(&tm_result,timebuf);


	fprintf(stdout,"STATUS: %8f %% done; %8f/sec :: %d of %d : %d errs %s",	// asctime() has a \n
			100.0*(double)Ctx->nTargetsDone/Ctx->nTargets,
			(double)(Ctx->nTargetsDone-old)/Ctx->alarmTime,
			Ctx->nTargetsDone,
			Ctx->nTargets,
			Ctx->errCount,
			timebuf);
	old=Ctx->nTargetsDone;
	signal(SIGALRM,handle_alarm);
	alarm(Ctx->alarmTime);
}
