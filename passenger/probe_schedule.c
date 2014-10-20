#include <assert.h>
#include <netinet/ip.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>

// for inet_ntop
#include <sys/socket.h>
#include <arpa/inet.h>


#include "passenger.h"
#include "packet_handlers.h"
#include "callbacks.h"

int needRedundantProbes(struct connection *con , struct trdata *tr, int endhost, int nat_or_firewall);

/*******************************************************************
 * void calc_next_probe(struct connection *, struct trdata *tr, int endhost, int nat_or_firewall)
 * 	figure out what the next probe should be
 * 	or if we are done
 * 	endhost == 1 if we just got a response from the endhost
 * 	nat_or_firewall == 1 if we just got a response from a nat or firewall
 *	
 * 	if done, print some stats
 *
 * 	This assume that there are no probes outstanding, and the next probe is relative to
 * 	the last probe sent.
 */
void calc_next_probe(struct connection *con , struct trdata *tr, int endhost, int nat_or_firewall)
{
	switch(tr->phase)
	{
		case PHASE_RPT:
			tr->iteration++;
			if(tr->iteration>=Iterations)
			{
				if(needRedundantProbes(con,tr,endhost,nat_or_firewall))
				{
					fprintf(tr->out,"TRANSITION: redoing packet trains ; need redundant probing\n");
					tr->iteration=0;
					tr->redundant++;
					trdata_initProbes(tr);
				}
				else
				{
					fprintf(tr->out,"TRANSITION: going from packet trains to traceroute probing\n");
					tr->iteration=0;
					tr->phase=PHASE_TR;
					trdata_initProbes(tr);
					// tr->nextTTL=tr->safettl+1;	// NO!
					tr->nextTTL=tr->highestReturnedTTL+1;	// start probing from 1 after the last icmp response we got
				}
			}
			return;
		case PHASE_TR:
			if(DepthFirst)
			{
				tr->nextTTL++;
				if(endhost || (tr->nextTTL>MaxTTL))	
				{
					tr->nextTTL=tr->safeTTL+1;
					tr->iteration++;
					if(tr->iteration>=Iterations)
						tr->done=1;
				}
			} 
			else
			{		// breadth first
				tr->iteration++;
				if(tr->iteration>=Iterations)
				{
					tr->iteration=0;
					tr->nextTTL++;
					if(endhost)
						tr->hitEndhost=1;	// remember if we hit it in a previous probe
					if((tr->nextTTL>MaxTTL)||(tr->hitEndhost))
					{
						tr->done=1;
						do_finished(con,tr);
					}
				}
			}
			return;
		default:
			fprintf(stderr,"Unknown phase %d for connection %d :: abort!!\n",
					tr->phase,tr->conId);
			abort();
			return;
	};
}

/**************************************************************************
 * struct connection *con , struct trdata *tr, int endhost, int nat_or_firewall)
 * 	look through the probes we've received and see if there is weird
 * 	load balancing.  If so, return 1, else return 0.
 * 	Also, return 0 if tr->redundant>=MAX_REDUNDANT_PROBES
 */


int needRedundantProbes(struct connection *con , struct trdata *tr, int endhost, int nat_or_firewall)
{
	int i,j;
	assert(con);
	assert(tr);
	if(tr->redundant>=MAX_REDUNDANT_PROBES)	// we have already had too many redundant probes
		return 0;
	for(i=1;i<Iterations;i++)
	{
		for(j=0;j<MaxTTL;j++)
		{
			// if the probes from 2 diff iterations were received and come from diff places
			if((tr->probes[i][j].status == PROBE_STATUS_RECEIVED) &&
					(tr->probes[i-1][j].status == PROBE_STATUS_RECEIVED) &&
					(tr->probes[i-1][j].ip != tr->probes[i][j].ip))
				return 1;
			// should prob also look at RR info for changes
		}
	}
	return 0;
}
