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
#include "probe_schedule.h"

char * MarcoPollo[] = {
	"Macro",
	"Payload",
	"Pollo",
	"TraceRoute"
};



/*********************************************************************
 * void icmpCB(struct connection * con ,struct packet *p, struct pcap_pkthdr* pcaphdr)
 * 	this gets called when we receive an ICMP packet that looks like it is destined
 * 	for this connection	-- should be an ICMP time-exceeded or dest unreach
 */
void icmpCB(struct connection * con ,struct packet *p, const struct pcap_pkthdr* pcaphdr)
{
	trdata *tr;
	char buf[BUFLEN];
	struct packet * bouncep;
	struct iphdr ip,bounceip;
	struct icmp_header icmp;
	struct timeval diff,now;
	int ttl,probe_num;
	int iteration;
	int rpt;
	int len;
	char ipoptions[MAX_IPOPTLEN];
	int nat_or_firewall;
	int err;
	int marcopollo= 0;
	struct mpls_header mpls;
	probe * cur_probes;

	len = BUFLEN;
	connection_get_name(con,buf,&len);
	packet_get_ip_header(p,&ip);
	packet_get_icmp_header(p,&icmp);
	len = BUFLEN;
	packet_get_data(p,buf,&len);
	// reconstruct the bounced packet from the icmp payload
	bouncep = packet_make_from_buf((struct iphdr *)buf,len);
	assert(bouncep);
	// get our per connection data
	tr = (trdata *) connection_get_app_data(con);
	assert(tr);
	packet_get_ip_header(bouncep,&bounceip);
	inet_ntop(AF_INET,&ip.saddr,buf,BUFLEN);
	// is this the icmp packet we were expecting?
	err = convert_ip_id(tr,bounceip.id,&iteration,&probe_num,&rpt);
	if(err)
	{ 
		fprintf(tr->out,"Received random ICMP message: packet id %d, sent id %d type=%d code=%d\n", 
				ip.id,bounceip.id,icmp.type,icmp.code);
		packet_free(bouncep);
		return;
	}
	probe_delete(con,bounceip.id);		// free up the id to probe mapping memory
	if(rpt==0)
	{
		ttl=probe_num;
		cur_probes=tr->probes[iteration];
		marcopollo = tr->probes[iteration][probe_num].type;
		tr->probes[iteration][probe_num].ip = ip.saddr;
		tr->probes[iteration][probe_num].nRR = 0;
	}
	else
	{
		tr->nProbesOutstanding[iteration]--;
		// snag the stored information off of the probe
		marcopollo = tr->probes[iteration][probe_num].type;
		ttl = tr->probes[iteration][probe_num].ttl;
		cur_probes=tr->probes[iteration];
		tr->probes[iteration][probe_num].ip = ip.saddr;
		tr->probes[iteration][probe_num].nRR=0;
	}
	if(tr->highestReturnedTTL<ttl)
		tr->highestReturnedTTL=ttl;

	// cancel scheduled timeout if it exists, and if we are done
	if(rpt )
	{
		if((tr->nProbesOutstanding[iteration]<=0)&&(cur_probes[0].timerID!=-1))
		{
			sc_cancel_timer(con,cur_probes[0].timerID);
			cur_probes[0].timerID=-1;		// we store the timerID in the *first* probe_num in rpt
		}
	}
	else if(cur_probes[probe_num].timerID!=-1)
	{
		sc_cancel_timer(con,cur_probes[probe_num].timerID);
		cur_probes[probe_num].timerID=-1;		// traceroute case 
	}
	// check the probe status
	switch(cur_probes[probe_num].status)
	{
		case PROBE_STATUS_SENT:	// normal case
			fprintf(tr->out,"- RECV TTL %d it=%d from %16s (%d)", ttl,iteration,buf,ip.ttl);
			break;
		case PROBE_STATUS_UNSENT:	// we never sent this probe: weird!
			fprintf(tr->out,"- UNSENT TTL %d it=%d from %16s (%d)", ttl,iteration,buf,ip.ttl);
			break;
		case PROBE_STATUS_TIMEDOUT:	// we sent this probe, but assumed it timedout
			fprintf(tr->out,"- OLD TTL %d it=%d from %16s (%d)", ttl,iteration,buf,ip.ttl);
			if(rpt)
				tr->nProbesOutstanding[iteration]++;		// un-double count this probe as being received; HACK
			break;
		case PROBE_STATUS_RECEIVED:	// got two responses for one probe!  also weird...
			fprintf(tr->out,"- DUPLICATE TTL %d it=%d from %16s (%d)", ttl,iteration,buf,ip.ttl);
			if(rpt)
				tr->nProbesOutstanding[iteration]++;		// un-double count this probe as being received
			break;
		default:
			fprintf(tr->out,"bad probe status: %d\n",cur_probes[probe_num].status);
			abort();
	};

	// Source classifier
	if(ip.saddr == bounceip.daddr)	// should never get TTL exceed from dst, unless it's a NAT
	{
		if(icmp.type==ICMP_TIME_EXCEEDED)
			fprintf(tr->out,"\tNAT\t");
		else 
			fprintf(tr->out,"\tFIREWALL?\t");
		nat_or_firewall=1;
	}
	else 
	{
		fprintf(tr->out,"\tROUTER\t");
		nat_or_firewall=0;
	}
			
	now=pcaphdr->ts;
	if(cur_probes[probe_num].matched)	// print probe rtt timing info, if available
	{
		// assert(now happened before then): Bad idea; on planetlab, this can be false :-(
		//assert(timercmp(&pcaphdr->ts,&cur_probes[probe_num].sendTime,>=));	
		timersub(&pcaphdr->ts,&cur_probes[probe_num].sendTime,&diff);
		fprintf(tr->out," rtt=%ld.%.6ld s t=%ld.%.6ld", diff.tv_sec,(long)diff.tv_usec,
				now.tv_sec,(long)now.tv_usec);
	}
	else
		fprintf(tr->out," NO MATCH t=%ld.%.6ld",now.tv_sec,(long)now.tv_usec);		// must be three tokens; to avoid post-processing difficulties
	len=MAX_IPOPTLEN;
	packet_get_ip_options(bouncep,ipoptions,&len);
	if(len>0)
		print_ip_options(ipoptions,len,&(cur_probes[probe_num]),tr->out);

	// print mpls info if this packet has it
	if(packet_get_mpls(bouncep,&mpls))
		fprintf(tr->out," MPLS,l=%d,CoS=%d,ttl=%d,S=%d",mpls.label, mpls.exp, mpls.ttl, mpls.s);
	if(packet_get_mpls(p,&mpls))	// HORRIBLE; can't you get your draft RFCs standardized!?
		fprintf(tr->out," MPLS,l=%d,CoS=%d,ttl=%d,S=%d,",mpls.label, mpls.exp, mpls.ttl, mpls.s);

	fprintf(tr->out," %s",MarcoPollo[marcopollo]);
	if(icmp.type!=ICMP_TIME_EXCEEDED)	// if we got a non-time exceeded message; shutdown connection before complaints
	{
		fprintf(tr->out," Non-time exceeded message: ICMP type=%d code=%d : ABORT!",icmp.type,icmp.code);
		if(icmp.type==ICMP_PARAMETERPROB)
			fprintf(tr->out," ICMP_PARAMETERPROB at index %d", icmp.un.paramprob.pointer);
		fprintf(tr->out,"\n");
		closeCB(con);
		packet_free(bouncep);
		return;
	}
	
	fprintf(tr->out,"\n");

	if(cur_probes[probe_num].status==PROBE_STATUS_SENT)
	{
		if(tr->phase!=PHASE_RPT || tr->nProbesOutstanding[iteration]<=0)	// are we done with this round of probe(s)?
		{
			calc_next_probe(con,tr,0,nat_or_firewall);	// only inc next probe if this was 
									// the last probe we were expecting
			if(!tr->done)
			{
				if(tr->phase == PHASE_RPT)
					sc_register_idle(idleCB_rpt,con,IdleTime);		// idle timer for rpt
				else
					sc_register_idle(idleCB_traceroute,con,IdleTime);	// idle timer to traceroute
			}
		}
	}
	cur_probes[probe_num].status=PROBE_STATUS_RECEIVED;	// mark probe has received
	// tell the incoming handler to ignore packets until we send another probe
	if(tr->phase!=PHASE_RPT)
		sc_register_in_handler(NULL,con);
	// wait for connection to be idle again
	packet_free(bouncep);
}

/***********************************************************************
 * void inCB(struct connection *con,struct packet *p ,struct pcap_pkthdr* pcaphdr)
 * 	the remote side sent us a packet
 */

void inCB(struct connection *con,struct packet *p ,const struct pcap_pkthdr* pcaphdr)
{
	trdata *tr;
	char buf[BUFLEN];
	struct iphdr ip;
	struct timeval diff,now;
	int ttl,iteration;
	int probe_num;

	tr = connection_get_app_data(con);
	assert(tr);
	if(!packet_is_redundant_ack(p,con))
		return;			// ignore non-redundant ack packets

	probe_num = ttl= tr->nextTTL;	// assume this packet is a response to the last probe we sent out 
	iteration = tr->iteration;
	packet_get_ip_header(p,&ip);
	inet_ntop(AF_INET,&ip.saddr,buf,BUFLEN);
	// cancel scheduled timeout
	if(tr->probes[iteration][probe_num].timerID!=-1)
	{
		sc_cancel_timer(con,tr->probes[iteration][probe_num].timerID);
		tr->probes[iteration][probe_num].timerID=-1;
	}
	if(tr->phase==PHASE_RPT)	
	{
		// something bad happened; maybe SafeTTL was a bad estimate?; should not get these in phase PHASE_RPT
		fprintf(tr->out,"BAD: got a probe response from ENDHOST: ttl=%d it=%d ignoring: t=%ld.%.6ld\n",
				ttl,iteration,now.tv_sec,(long)now.tv_usec);
		return;
	}	
	// print recv message
	fprintf(tr->out,"- RECV TTL %d it?=%d from %16s (%d)\tENDHOST\t", 
			ttl,tr->iteration,buf,ip.ttl);
	now=pcaphdr->ts;
	if(tr->probes[iteration][probe_num].matched)	// print timing info if available
	{
		// assert(now happened before then): Bad idea; on planetlab, this can be false :-(
		// assert(timercmp(&pcaphdr->ts,&tr->tr_probes[iteration][probe_num].sendTime,>=));	
		timersub(&pcaphdr->ts,&tr->probes[iteration][probe_num].sendTime,&diff);
		fprintf(tr->out," rtt=%ld.%.6ld s t=%ld.%.6ld TraceRoute?\n", 
				diff.tv_sec,(long)diff.tv_usec,
				now.tv_sec,(long)now.tv_usec);
	}
	else
		fprintf(tr->out," NO MATCH t=%ld.%.6ld\n",now.tv_sec,(long)now.tv_usec);		// must be three tokens; to avoid post-processing difficulties
	// was this the one we were expecting?
	if(tr->probes[iteration][probe_num].status==PROBE_STATUS_SENT)	
		calc_next_probe(con,tr,1,0);		// then schedule next probe
	tr->probes[iteration][probe_num].status=PROBE_STATUS_RECEIVED;	// probes as received
	// Do Not Schedule the Idle Timer unless there is more to do
	if(!tr->done)
	{
		sc_register_idle(idleCB_traceroute,con,IdleTime);	// idle timer for traceroute
	}
}
/***********************************************************************/
void outCB(struct connection * con ,struct packet * p ,const struct pcap_pkthdr* pcaphdr)
{
	trdata *tr;
	char buf[BUFLEN];
	int len;
	struct iphdr ip;
	int iteration,probe_num,rpt;
	int err;
	probe * prb;
	tr = connection_get_app_data(con);	
	assert(tr);
	packet_get_ip_header(p,&ip);
	err=convert_ip_id(tr,ip.id,&iteration,&probe_num,&rpt);
	if(!err)
	{
		// this is one of our probes
		if(probe_num<0 
				|| iteration < 0 
				|| iteration>=Iterations )
		{
			fprintf(tr->out,"WEIRD: random probe-looking id %d: it=%d probe_num=%d\n",
					ip.id,iteration, probe_num);
			return;
		}
		if(!rpt)
		{
			if(probe_num>MaxTTL)
			{
				fprintf(tr->out,"WEIRD: random-probe looking id %d: it=%d probe_num=%d\n",
						ip.id,iteration, probe_num);
				return;		// probe_num out of range
			}
			prb = &(tr->probes[iteration][probe_num]);
		}
		else
		{
			if(probe_num>tr->nProbes[iteration])
			{
				fprintf(tr->out,"WEIRD: random probe-looking id %d: it=%d probe_num=%d\n",
						ip.id,iteration, probe_num);
				return;		// probe_num out of range
			}
			prb = &(tr->probes[iteration][probe_num]);
		}
		if(prb->status!=PROBE_STATUS_SENT)	// last sanity checks
		{
			fprintf(tr->out,"WEIRD: random probe-looking id %d: it=%d probe_num=%d\n",
					ip.id,iteration, probe_num);
			return;
		}
		// found outgoing probe: record the outgoing time
		// record the outgoing time as libpcap saw it
		prb->sendTime = pcaphdr->ts;	
		prb->matched=1;
		return;
	}
	// else not a probe; see if we need to update our lastDataPacket
	len=BUFLEN;
	packet_get_data(p,buf,&len);
	if(len==0)
		return;		// nothing new; return
	if(tr->lastDataPacket)
		packet_free(tr->lastDataPacket);
	// save this packet to be reused as a probe
	tr->lastDataPacket=packet_duplicate(p);
	if(tr->probeType==SYNACK_PROBE)
		tr->probeType=DATA_PROBE;
	if(tr->phase==PHASE_WAITING)	// set idle timer once we get the first data packet
	{
		tr->safeTTL=guess_safe_ttl(con);
		if(tr->safeTTL>0)		// if it's safe, do rpt
		{
			tr->phase=PHASE_RPT;
			sc_register_idle(idleCB_rpt,con,IdleTime);	
		}
		else				// else just do standard traceroute
		{				
			fprintf(tr->out,"Skipping RPT: safe_ttl of %d is too close for rpt\n",tr->safeTTL);
			tr->phase=PHASE_TR;
			sc_register_idle(idleCB_traceroute,con,IdleTime);	
		}
	}
}
