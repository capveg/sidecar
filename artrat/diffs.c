/**********************************************************************************
 * ARTRAT:	tracks connections given the tcpdump style string given,
 *		injects probes into connection to figure out where bottlenecks are
 *				- capveg '06 
 */

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <values.h>
#include <arpa/inet.h>

#include "sidecar.h"
#include "artrat.h"
#include "diffs.h"

static int timeval2routerts(struct timeval);

/*****************************************************************************************
 * void diffPacketProbes(artratcon * ac);
 * 	output the difference in times between probes, along with current cong delay, and
 * 	most likely suspect
 */


void diffPacketProbes(artratcon * ac)
{
	switch(CompareType)
	{
		case COMP_TYPE0:
			return diffPacketProbes0(ac);
		case COMP_TYPE1:
			return diffPacketProbes1(ac);
		case COMP_TYPE2:
			return diffPacketProbes2(ac);
		case COMP_TYPE3:
			return diffPacketProbes3(ac);
		case COMP_TYPE4:
			return diffPacketProbes4(ac);
		case COMP_TYPE5:
			return diffPacketProbes5(ac);
		default:
			fprintf(stderr,"!!! unknown CompareType=%d\n",CompareType);
			abort();
	}
}



/************************************************************************/
void diffPacketProbes0(artratcon *ac)
{
	int i,j;
	int value;
	for(j=0;j<(ac->nIcmpProbes-1);j++)
	{
		if(ac->icmpprobes[j]->status!=PROBE_RECV||ac->icmpprobes[j+1]->status!=PROBE_RECV)
			continue;
		printf("%d:%d : ",ac->ICMPProbeCount,j);
		for(i=4;i<40;i+=4)
		{
			value=ntohl(*(int*)&ac->icmpprobes[j+1]->options[i])-
				ntohl(*(int*)&ac->icmpprobes[j]->options[i]);
			printf("%d=%d ", i/4,value); // diff probes, by entry in ms 
		}
		printf("; bTTL=%lf aTTL=%lf cong=%lf\n", (double)ac->usBaseRtt/1000,(double)ac->usVJRtt/1000,((double)ac->usVJRtt-ac->usBaseRtt)/1000);
	}
}
/************************************************************************/
void diffPacketProbes1(artratcon *ac)
{
	int i,j;
	int value;
	for(j=0;j<(ac->nIcmpProbes-1);j++)
	{
		if(ac->icmpprobes[j]->status!=PROBE_RECV||ac->icmpprobes[j+1]->status!=PROBE_RECV)
			continue;
		printf("%d:%d : ",ac->ICMPProbeCount,j);
		for(i=4;i<40;i+=4)
		{
			value=ntohl(*(int*)&ac->icmpprobes[j+1]->options[i]);
			printf("%d=%d ", i/4,value); // diff probes, by entry in ms 
		}
		printf("; bTTL=%lf aTTL=%lf cong=%lf\n", (double)ac->usBaseRtt/1000,(double)ac->usVJRtt/1000,((double)ac->usVJRtt-ac->usBaseRtt)/1000);
	}
}
/************************************************************************/
void diffPacketProbes2(artratcon *ac)
{
	int i,j;
	int value;
	for(j=0;j<ac->nIcmpProbes;j++)
	{
		if(ac->icmpprobes[j]->status!=PROBE_RECV)
			continue;
		printf("%d:%d : ",ac->ICMPProbeCount,j);
		for(i=4;i<(IP_MAX_OPTLEN-4);i+=4)
		{
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[i])-
				ntohl(*(int*)&ac->icmpprobes[j]->options[i+4]);
			printf("%d=%+d ", i/4,value); // diff probes, by entry in ms 
		}
		printf("; bTTL=%lf aTTL=%lf cong=%lf\n", (double)ac->usBaseRtt/1000,(double)ac->usVJRtt/1000,((double)ac->usVJRtt-ac->usBaseRtt)/1000);
	}
}


/************************************************************************/
void diffPacketProbes3(artratcon *ac)
{
	int i,j;
	unsigned int value;
	u32 ip;
	char buf[BUFLEN];
	
	for(j=0;j<ac->nIcmpProbes;j++)
	{
		printf("%d:%d : ",ac->ICMPProbeCount,j);
		for(i=4;i<(IP_MAX_OPTLEN-4);i+=8)
		{
			ip=*(u32*)&ac->icmpprobes[j]->options[i];
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[i+4]);
			inet_ntop(AF_INET,&ip,buf,BUFLEN);
			printf("%u@%s ",value, buf ); // diff probes, by entry in ms 
		}
		printf("; bTTL=%lf aTTL=%lf cong=%lf\n", (double)ac->usBaseRtt/1000,(double)ac->usVJRtt/1000,((double)ac->usVJRtt-ac->usBaseRtt)/1000);
	}
}


/************************************************************************
 * 	assumes 1 probe/pack ; compare vs last probe
 * 	- first time this is called, print nothing
 */
void diffPacketProbes4(artratcon *ac)
{
	int i,j,k;
	int value;
	int nStamps;
	struct timeval diff;

	
	for(j=0;j<ac->nIcmpProbes;j++)
	{
		if(ac->icmpprobes[j]->status!=PROBE_RECV)
			continue;
		printf("%d:%d pRTT ",ac->ICMPProbeCount,j);
		if((ac->icmpprobes[j]->sent.tv_sec==0)&&(ac->icmpprobes[j]->sent.tv_usec==0))
			printf("?? ");
		else
		{
			timersub(&ac->icmpprobes[j]->recv,&ac->icmpprobes[j]->sent,&diff);
			printf("%ld.%.6ld ",diff.tv_sec,diff.tv_usec);
		}
		printf(" iRTT %lf ",(double)ac->usLastRtt/1000000);
		nStamps= (ac->icmpprobes[j]->options[2]-5)/4;		// options[2]=41 if full --> 9 stamps
		if(nStamps!=ac->nStamps)
		{
			printf("TIMESTAMPS CHANGED: was %d now %d\n",ac->nStamps,nStamps);
			ac->nStamps=nStamps;
		}
		if(nStamps>0)
		{
			// hack in the hop0->hop1 delta
			value = timeval2routerts(ac->icmpprobes[j]->sent);
			printf("%d=%+d ", 0,value); // print raw time
		}
		for(i=0;i<nStamps;i++)
		{
			k = i*4+4;
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[k]);
			printf("%d=%u ", i+1,value); // print raw time
		}
		if(nStamps>0)
		{
			// hack in the hop1->hop0 delta
			value = timeval2routerts(ac->icmpprobes[j]->recv)  ;
			printf("%d=%+d ", nStamps,value); // diff probes, by entry in ms 
		}
		printf("; bRTT=%lf #=%d(%.2f%%) aRTT=%lf %ld.%.6ld\n", 
				(double)ac->usBaseRtt/1000000,ac->ProbeCount-ac->DropCount,
				100*(double)ac->DropCount/ac->ProbeCount,
				(double)ac->usVJRtt/1000000,
				ac->icmpprobes[0]->recv.tv_sec,ac->icmpprobes[0]->recv.tv_usec);
		for(i=0;i<nStamps;i++)	// update clock precision counters
		{
			k = i*4+4;
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[k]) - ac->lastclock[i];
			if((value>0)&&(value<ac->clockprecision[i]))
				ac->clockprecision[i]=value;
			ac->lastclock[i]=ntohl(*(int*)&ac->icmpprobes[j]->options[k]);
		}
	}
}

/************************************************************************
 * 	compare vs min probe
 * 	- first time this is called, print nothing, calc init mins
 *
 * 	- do some extra work to hack in the sent/recv times from the local host
 * 		as xmin[0] and xmin[9] respectively
 */
void diffPacketProbes5(artratcon *ac)
{
	int i,j,k;
	int value;
	int nStamps;
	struct timeval diff;

	// if this is our first time here and we have data
	if(ac->xminNeedInit&&(ac->icmpprobes[0]->status==PROBE_RECV))
	{
		// then record the data
		ac->xminNeedInit=0;
		for(j=0;j<ac->nIcmpProbes;j++)
		{
			if(ac->icmpprobes[j]->status!=PROBE_RECV)
				continue;
			nStamps= (ac->icmpprobes[j]->options[2]-5)/4;		// options[2]=41 if full --> 9 stamps
			for(i=0;i<(nStamps-1);i++)		// calc the deltas between each router ts
			{	
				k = i*4+4;
				value= ntohl(*(int*)&ac->icmpprobes[j]->options[k+4])-	// calc differences
					ntohl(*(int*)&ac->icmpprobes[j]->options[k]);
				if(ac->xmin[i+1]>value)
					ac->xmin[i+1]=value;
			}
			for(i=0;i<nStamps;i++)	// init clock precision counters
			{
				k = i*4+4;
				ac->lastclock[i]=ac->icmpprobes[j]->options[k];
			}
			if(nStamps>0)
			{	
				// hack in the hop0->hop1 delta
				value = ntohl(*(int*)&ac->icmpprobes[j]->options[4]) - 
					timeval2routerts(ac->icmpprobes[j]->sent);
				if(value<ac->xmin[0])
					ac->xmin[0]=value;
				// hack in the hop1->hop0 delta
				value = timeval2routerts(ac->icmpprobes[j]->recv) - 
					ntohl(*(int*)&ac->icmpprobes[j]->options[4*nStamps]);
				if(ac->xmin[nStamps]>value)
					ac->xmin[nStamps]=value;
			}
			ac->nStamps=nStamps;
		}
		return;
	}
	
	for(j=0;j<ac->nIcmpProbes;j++)
	{
		if(ac->icmpprobes[j]->status!=PROBE_RECV)
			continue;
		printf("%d:%d pRTT ",ac->ICMPProbeCount,j);
		if((ac->icmpprobes[j]->sent.tv_sec==0)&&(ac->icmpprobes[j]->sent.tv_usec==0))
			printf("?? ");
		else
		{
			timersub(&ac->icmpprobes[j]->recv,&ac->icmpprobes[j]->sent,&diff);
			printf("%ld.%.6ld ",diff.tv_sec,diff.tv_usec);
		}
		printf(" iRTT %lf ",(double)ac->usLastRtt/1000000);
		nStamps= (ac->icmpprobes[j]->options[2]-5)/4;		// options[2]=41 if full --> 9 stamps
		if(nStamps!=ac->nStamps)
		{
			printf("TIMESTAMPS CHANGED: was %d now %d\n",ac->nStamps,nStamps);
			ac->nStamps=nStamps;
		}
		if(nStamps>0)
		{
			// hack in the hop0->hop1 delta
			value = ntohl(*(int*)&ac->icmpprobes[j]->options[4]) - 
				timeval2routerts(ac->icmpprobes[j]->sent);
			printf("%d=%+d ", 0,value-ac->xmin[0]); // diff probes, by entry in ms 
			if(ac->xmin[0]>value)
				ac->xmin[0]=value;
		}
		for(i=0;i<(nStamps-1);i++)
		{
			k = i*4+4;
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[k+4])-
				ntohl(*(int*)&ac->icmpprobes[j]->options[k]);
			printf("%d=%+d ", i+1,value-ac->xmin[i+1]); // diff probes, by entry in ms 
			if(ac->xmin[i+1]>value)
				ac->xmin[i+1]=value;
		}
		if(nStamps>0)
		{
			// hack in the hop1->hop0 delta
			value = timeval2routerts(ac->icmpprobes[j]->recv) - 
				ntohl(*(int*)&ac->icmpprobes[j]->options[4*nStamps]);
			printf("%d=%+d ", nStamps,value-ac->xmin[nStamps]); // diff probes, by entry in ms 
			if(ac->xmin[nStamps]>value)
				ac->xmin[nStamps]=value;
		}
		printf("; bRTT=%lf #=%d(%.2f%%) aRTT=%lf %ld.%.6ld\n", 
				(double)ac->usBaseRtt/1000000,ac->ProbeCount-ac->DropCount,
				100*(double)ac->DropCount/ac->ProbeCount,
				(double)ac->usVJRtt/1000000,
				ac->icmpprobes[0]->recv.tv_sec,ac->icmpprobes[0]->recv.tv_usec);
		for(i=0;i<nStamps;i++)	// update clock precision counters
		{
			k = i*4+4;
			value=ntohl(*(int*)&ac->icmpprobes[j]->options[k]) - ac->lastclock[i];
			if((value>0)&&(value<ac->clockprecision[i]))
				ac->clockprecision[i]=value;
			ac->lastclock[i]=ntohl(*(int*)&ac->icmpprobes[j]->options[k]);
		}
	}
}
/******************************************************************************************
 * int timeval2routerts(struct timeval tv)
 * 	turn a locally generated tv struct into 
 * 	something we can compare to a router's timestamp
 * 	i.e., miliseconds from midnight
 */

int timeval2routerts(struct timeval tv)
{
	int sec,ms;
	sec = tv.tv_sec % (60*60*24);	// number of seconds into today
	ms = tv.tv_usec/1000;	// number of ms 
	if((tv.tv_usec%1000)>500)
		ms++;		// cut our imprescion down to .5ms by rounding
	// sidecarlog(LOGAPP," %ld.%.6ld == %ld ms\n",tv.tv_sec,tv.tv_usec,sec*1000+ms);
	return sec*1000+ms;
}
