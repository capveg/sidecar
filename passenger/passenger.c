/**************************************************************************************
 * 	'Passenger' is the driver module for sidecar
 * 		"He looks through his window, and what does he see" -- Iggy Pop
 * 		
 * Goal: 
 *	Use litany of TCP injection techniques to discover network topology
 *			- capveg '06
 */



#include <assert.h>
#include <errno.h>
#include <math.h>
#include <netinet/ip.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <time.h>
#include <values.h>

// for inet_ntop
#include <sys/socket.h>
#include <arpa/inet.h>


#include "passenger.h"
#include "packet_handlers.h"
#include "callbacks.h"
#include "probe_schedule.h"

#define RLIM_MAX_MEM (100*1024*1024)

// globals
int MaxMemKb=100*1024;
int MaxTTL=30;
int MSS=1460;		// MTU=1500-ip (20) - tcp(20)
int Planetlab=0;
int Iterations=6;
int UseRR=1;
int DebugLevel=LOGINFO|LOGCRIT;
char *OutDir=PASSENGER_OUTDIR;
char *TempOutDir=PASSENGER_OUTDIR"-tmp";	
char * EthDev=NULL;
int Port=0;
long int IdleTime=50000;	// should be at least 4 time slices to avoid application delay
long int MAXRTO=5000000;	// don't wait longer than 5s, no matter what TCP tells us; 1s = q len, 5 = big number
int DepthFirst=0;		// foreach ttl { foreach count { send probe}} or the other way?
int RPT_payload = 10000;	// 1/3rd of RPT paper... don't want to send 30k/40 bytes = 700 packets/probe
int SafeDistance=3;		// the number of hops we should stay away from endhosts
int MaxSafeTTL=14;		// our safe distance metric might be off, so put an upper limit on it
int ForceCloseTimeout=(1000*1000*120);	// force the connection to 1 minutes
int SkipFinAck=0;
int AlarmTime=5;		// seconds between checking the disk usage
float DiskSoftThreshold=0.10;	// no softthreshold by default; just go to hard
float DiskHardThreshold=0.10;
int UseLightTrain=1;		// set to Zero to use Big recursive packet trains

char * ProbeString[]= {
        "!!!BUG!!!",
        "SYNACK",
        "FINACK",
        "DATA"
};


static void usage(char *,char*);
static void alarm_handler(int);
static void parse_args(int argc,char *argv[]);



/***********************************************************************
 * int main(int argc, char * argv[])
 * 	parse some args, register some callbacks, and call sc_main_loop()
 */

int main(int argc, char * argv[])
{
	int err;
	char buf[BUFLEN+1];
	//struct rlimit lims;
	parse_args(argc,argv);
	if(Port<=0)
		usage("need to specify port option via -p",NULL);
	// match only stuff on the specifed port and that has the DF bit set
	// we will unset DF if we don't want the filter to have to deal with
	// these packets
	snprintf(buf,BUFLEN, 
             "( tcp src port %d or ( tcp dst port %d and ( ip[6:1] & 0x40 = 0x40 ) ) )", 
             Port, Port);
	// if we are on planetlab/vnet, then don't do the FinAck stuff
	/* This seems to work sometimes -- weird!
	if(vnet_test())
		SkipFinAck=1;
		*/

	// set rlimits on mem so we don't get too big
	/**** causing this weird 'Unknown error.' -- how fuck'ed this that?!
	lims.rlim_cur=lims.rlim_max=RLIM_MAX_MEM;
	err=setrlimit(RLIMIT_AS,&lims);
	if(err)
	{
		perror("setrlimit");
		abort();
	}
	*/


	// setup sidecar callbacks
	sc_init(buf,EthDev,Planetlab);	
	sc_setlogflags(DebugLevel);
	sc_set_max_mem(MaxMemKb);
	sc_register_connect(connectCB);
	srand(time(NULL));
	mkdir(OutDir,0755);	// fail silently if it exists
	mkdir(TempOutDir,0755);	// fail silently if it exists
	signal(SIGALRM,alarm_handler);
	alarm(AlarmTime);
	sc_do_loop();		// pass control to sidecar; called event handlers
	err=rmdir(TempOutDir);
	if(err)
		perror("rmdir TempOutDir");
	do
	{
		err=rmdir(OutDir);
		if(err)
		{
			if(errno==ENOTEMPTY)
			{
				sleep(5);
				continue;
			}
			perror("rmdir OutDir");
		}
	}while(err!=0);

	return 0;
}

/*****************************************************************
 * void parse_args(int argc,char *argv[]);
 *
 */

void parse_args(int argc,char *argv[])
{
	int c;
	while((c=getopt(argc,argv,"t:p:P:fi:I:D:c:m:M:d:rs:"))!=EOF)
	{
		switch(c)
		{
			case 't':
				DiskSoftThreshold=atof(optarg);
				if(DiskSoftThreshold<0)
				{
					fprintf(stderr,"Invalid threshold %f\n",DiskSoftThreshold);
					exit(1);
				}
				break;
			case 'P':
				RPT_payload=atoi(optarg);
				if(RPT_payload<=0)
				{
					fprintf(stderr,"Invalid RPT_payload %d\n",RPT_payload);
					exit(1);
				}
				break;
			case 'p':
				Port= atoi(optarg);
				if((Port<=0) || (Port>65535))
				{
					fprintf(stderr,"Invalid Port %d\n",Port);
					exit(1);
				}
				break;
			case 'f':
				DepthFirst=1;
				break;
			case 'i':
				IdleTime=atol(optarg);
				break;
			case 'I':
				EthDev=strdup(optarg);
				break;
			case 'D':
				DebugLevel=atoi(optarg);
				break;
			case 'c':
				Iterations=atoi(optarg);
				break;
			case 'm':
				MaxTTL=atoi(optarg);
				break;
			case 'M':
				MaxMemKb=atoi(optarg);
				break;
			case 'd':
				OutDir=strdup(optarg);
				break;
			case 'r':
				UseRR=!UseRR;
				break;
			case 's':
				SafeDistance=atoi(optarg);
				break;
			default:
				usage("invalid arg",(char *) &optopt);
		};
	}
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
			"passenger [options] -p port\n\n"
			"	-i usIdleTime			[%ld]\n"
			"	-I eth0       			[auto]\n"
			"	-P rpt_payload			[%d]\n"
			"	-D debuglevel			[%d]\n"
			"	-c count			[%d]\n"
			"	-m maxttl			[%d]\n"
			"	-M MaxMemUsedKB			[%d]\n"
			"	-f 	-- depth first		[breadth first]\n"
			"	-d outdir			['%s']\n"
			"	-s SafeDistance			[%d]\n"
			"	-t DiskSoftThreshold		[%f]\n"
			"	-r 	-- use record route	[on]\n",
			IdleTime,RPT_payload,DebugLevel,Iterations,MaxTTL,MaxMemKb,OutDir,SafeDistance,DiskSoftThreshold);
	exit(1);
}


/**********************************************************************
 * trdata * trdata_create(struct connection * con)
 * 	create the connection specific data
 */

trdata * trdata_create(struct connection * con)
{
	trdata *tr;
	char buf[BUFLEN+1];
	char filename[BUFLEN+1];
	int i;
	int len;
	char *ptr;

	tr = malloc(sizeof(trdata));
	assert(tr);
	tr->done=0;
	tr->forceCloseID=-1;
	gettimeofday(&tr->starttime,NULL);
	tr->conId = connection_get_id(con);
	tr->con=con;
	tr->iteration=0;
	tr->redundant=0;
	tr->probeType=SYNACK_PROBE;
	tr->highestReturnedTTL=0;
	tr->hitEndhost=0;
	// create the output file 
	if(DebugLevel&DEBUG2STDERR)
	{
		tr->out=stdout;
	}
	else
	{
		// make "data-source,port-dst,port-conid" for the output file name
		len=BUFLEN;
		connection_get_name(con,buf,&len);
		snprintf(filename,BUFLEN,"%s/data-%s-%d",TempOutDir,buf, connection_get_id(con));
		while((ptr=index(filename,':')))		// change all ':'s to commas b/c gmake blows and can't handle colons in prereq file names
			*ptr=',';
					
		tr->out = fopen(filename,"a");
		if(!tr->out)
		{
			fprintf(stderr,"Tried to open %s\n",filename);
			perror("trdata_create::fopen");
			abort();
		}
		setvbuf(tr->out,tr->outFileBuf,_IOFBF,OUTFILEBUFSIZE);	// increase buffering b/c planetlab is slow
	}
	// create the probes tr data structures
	tr->probes = malloc(sizeof(probe*)*Iterations);
	assert(tr->probes);
	// fill them in
	tr->nProbes= malloc(sizeof(int)*Iterations);
	assert(tr->nProbes);
	tr->nProbesOutstanding= malloc(sizeof(int)*Iterations);
	assert(tr->nProbesOutstanding);
	for(i=0;i<Iterations;i++)
	{
		tr->probes[i] = malloc(sizeof(probe)*(MaxTTL+1));
		assert(tr->probes[i]);
	}
	trdata_initProbes(tr);
	// rest of structure
	tr->safeTTL=0;		// need to guess, but assume not safe
	tr->nextTTL=1;		// start TR at one; this gets changed later when we get an 
				//	estimate on safeTTL
	tr->phase=PHASE_WAITING;
	tr->lastDataPacket=NULL;
	tr->nextProbeId=connection_get_ip_id(con);
	tr->nextProbeId=~tr->nextProbeId;
	return tr;
}

void trdata_initProbes(trdata *tr)
{
	int i,j;
	for(i=0;i<Iterations;i++)
	{
		assert(tr->probes[i]);
		for(j=0;j<=MaxTTL;j++)
		{
			tr->probes[i][j].matched=0;
			tr->probes[i][j].status=PROBE_STATUS_UNSENT;
			tr->probes[i][j].timerID=-1;
		}
		tr->nProbes[i]=-1;
		tr->nProbesOutstanding[i]=-1;
	}
}

/***********************************************************************
 * void trdata_free(trdata * tr)  
 * 	clean up the connection specific data
 */

void trdata_free(trdata * tr)	// clean up tr data structure
{
	int i,j;
	assert(tr);
	char filename[BUFLEN],dstname[BUFLEN];
	char buf[BUFLEN];
	int err,len;
	char * ptr;

	// cancel the timeouts
	for(j=0;j<Iterations;j++)
	{
		if(tr->probes[j])	// if we got far enought to allocate this
		{
			for(i=0;i<MaxTTL;i++)
			{
				if(tr->probes[j][i].timerID!=-1)
				{
					sc_cancel_timer(tr->con,tr->probes[j][i].timerID);
					tr->probes[j][i].timerID=-1;
				}
			}
			free(tr->probes[j]);
		}
	}
	free(tr->probes);
	free(tr->nProbesOutstanding);
	free(tr->nProbes);
	if(tr->lastDataPacket)
		packet_free(tr->lastDataPacket);
	if(!(DebugLevel&DEBUG2STDERR))		// for the love of God don't close stdout! horrible bug
	{
		fclose(tr->out);		
		// move the data file from the temp diectory to the data directory
		len=BUFLEN;
		connection_get_name(tr->con,buf,&len);
		snprintf(dstname,BUFLEN,"%s/data-%s-%d",OutDir,buf, connection_get_id(tr->con));
		snprintf(filename,BUFLEN,"%s/data-%s-%d",TempOutDir,buf, connection_get_id(tr->con));
		while((ptr=index(filename,':')))		// change all ':'s to commas b/c gmake blows and can't handle colons in prereq file names
			*ptr=',';
		while((ptr=index(dstname,':')))			// change all ':'s to commas b/c gmake blows and can't handle colons in prereq file names
			*ptr=',';
		err=rename(filename,dstname);
		if(err)
			fprintf(stderr,"Error %d moving %s to %s: %s\n",
					err, filename, dstname,strerror(errno));
	}
	free(tr);
}

/***********************************************************************
 * void print_ip_options(char *options, int len);
 *	parse the ip options array passed, and print representations of it
 *	don't print an EOLN 
 */

void print_ip_options(char *options, int optlen, probe *p,FILE * out)
{
	char buf[BUFLEN];
	int len;
	int i,j;
	assert(p);
	fprintf(out," ");
	p->nRR=0;
	for(i=0;i<optlen;i++)
	{
		switch(options[i])
		{
			case IPOPT_NOOP:
				// fprintf(out,"NOP, ");
				break;
			case IPOPT_EOL:
				return;		// end of list
			case IPOPT_RR:
				fprintf(out,"RR, ");
				len=options[i+2];		// pointer
				for(j=i+3;j<(i+len-1);j+=4)
				{
					inet_ntop(AF_INET,&options[j],buf,BUFLEN);
					fprintf(out,"hop %d %s , ", ((j-i-3)/4)+1,buf); 
					p->rr[p->nRR++]=*(u32 *)&options[j];
				}
				i+=options[i+1];		// total len
				break;
			default:
				fprintf(out,"OPT=%d(%d) ",options[i],i);
				break;
		}
	}
}
/*************************************************************************
 * void do_finished(struct connection *con, struct trdata *tr)
 * 	call this when done with a specific connection
 */

void do_finished(struct connection *con, struct trdata *tr)
{
	// cleanup this connection stuff, and print scantime
	// cuz we're done with this connection
	char buf[BUFLEN];
	int len=BUFLEN;
	struct timeval diff;
	tr->done=1;
	connection_get_name(con,buf,&len);
	gettimeofday(&diff,NULL);
	if(diff.tv_usec<tr->starttime.tv_usec)
	{
		diff.tv_sec--;
		diff.tv_usec+=1000000;
	}
	diff.tv_sec-=tr->starttime.tv_sec;
	diff.tv_usec-=tr->starttime.tv_usec;
	fprintf(tr->out,"%s scan done :: %ld.%.6ld\n",buf,diff.tv_sec,(long)diff.tv_usec);
	// unregister callbacks
	sc_register_idle(NULL,con,-1);
	sc_register_icmp_in_handler(NULL,con);
	sc_register_in_handler(NULL,con);
	sc_register_out_handler(NULL,con);
	// trdata_free(tr); don't call this here!  it's called in closeCB
}

/***********************************************************************************
 * int guess_safe_ttl(struct connection *);
 * 	guess a ttl to endhost based on their ttl to us, then back off SAFE_DISTANCE hops
 */

int guess_safe_ttl(struct connection *con)
{
	int ttl;
	if(SafeDistance==0)
		return 11;		// throw caution to the wind!
	ttl = connection_get_remote_ttl(con);
	if(ttl<=64)
	{
		ttl=64-ttl;
	}
	else if(ttl<=128)
	{
		ttl=128-ttl;
	}
	else 
	{
		ttl=256-ttl;
	}
	if(ttl>MaxTTL)
		ttl=MaxTTL;
	return MIN(MAX(ttl-SafeDistance,0),MaxSafeTTL);
}

/**************************************************************************************
 * void alarm_handler(int ignore)
 * 	every ctx->alarmTime seconds, call statfs to make sure we aren't below
 * 	ctx->diskThreasholdSoft of available disk capacity
 * 		if we are, print error message and sleep a bit and try again
 * 	if we are below ctx->diskThreasholdHard
 * 		then print err and abort()
 */

void alarm_handler(int ignore)
{
	struct statfs sbuf;
	int err;
	float percent;
	struct timeval now;

	do{
		err = statfs(OutDir,&sbuf);
		if(err != 0)
		{
			perror("statfs");
			assert(err == 0);
		}
		percent = (float)sbuf.f_bavail/sbuf.f_blocks;
		if(percent>=DiskSoftThreshold)
		{
			// disk is fine; just reschedule for later
			signal(SIGALRM,alarm_handler);
			alarm(AlarmTime);
			return;
		}
		if(percent<DiskHardThreshold)
		{
			fprintf(stderr,"!!!! Available space below DiskHardThreshold (%f %% < %f %%): aborting!\n",
					percent,DiskHardThreshold);
			abort();
		}
		gettimeofday(&now,NULL);
		fprintf(stderr,"!!!! %ld.%.6ld Available space below DiskSoftThreshold (%f %% < %f %%): sleeping\n",
				now.tv_sec,now.tv_usec,percent,DiskSoftThreshold);
		sleep(1);	// this sleep totally suspends *all* processing
	} while(percent<DiskSoftThreshold);

}
