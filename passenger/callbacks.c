#include <assert.h>
#include <errno.h>
#include <netinet/ip.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/time.h>
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
#include "mktrain.h"



/*********************************************************************
 * void connectCB(struct connection *con)
 * 	this gets called when sidecar discovers a new connection
 */

void connectCB(struct connection *con)
{
	trdata *tr;
	char buf[BUFLEN];
	int len=BUFLEN;
	struct timeval now;

	gettimeofday(&now,NULL);
	connection_get_name(con,buf,&len);
	tr = trdata_create(con);
	fprintf(tr->out, "%s :: new connection: id = %d time=%ld.%.6ld\n",
		buf, connection_get_id(con),now.tv_sec,(long)now.tv_usec);
	connection_set_app_data(con,tr);
	tr->safeTTL=guess_safe_ttl(con);
	tr->forceCloseID = sc_register_timer(forceCloseCB,con,ForceCloseTimeout,NULL);
	// register all of the call backs
	sc_register_icmp_in_handler(icmpCB,con);
	sc_register_close(closeCB,con);
	sc_register_timewait(timewaitCB,con);
	sc_register_out_handler(outCB,con);
}
/*********************************************************************
 * void idleCB_rpt(struct connection *con)
 * 	this func gets called when the monitored connection has no outstanding
 * 	data and tr->phase == PHASE_RPT
 */

void idleCB_rpt(struct connection *con)
{
	struct packet **packets;
	int nPackets;
	trdata *tr;
	int payload;
	int i,err;
	long rtt,mdev,count,rto;
	struct timeval now;
	char buf[BUFLEN];
	int len = BUFLEN;
	int useRR;

	connection_get_name(con,buf,&len);
	tr = (trdata *) connection_get_app_data(con);
	assert(tr);
	assert(tr->phase==PHASE_RPT);
	assert(tr->safeTTL>=0);

	payload = RPT_payload;
	// make the array of packets to be sent
	useRR = UseRR?(tr->iteration+1)%2:0;	// if UseRR, then set useRR==1 everyother iteration, else 0
	if(UseLightTrain)
		packets = make_light_packet_train(con,tr,tr->safeTTL,useRR,&nPackets);
	else
		packets = make_recursive_packet_train(con,tr,&payload,tr->safeTTL,useRR,&nPackets);
	assert(packets);

	// send packets
	err=packet_send_train(packets,nPackets);
	if(err!=nPackets)
	{
		fprintf(tr->out,"%s -- short send: error err=%d, strerror='%s'\n",
				buf,err,strerror(errno));
	}
	for(i=0;i<nPackets;i++) {
		packet_free(packets[i]);	// clean up packets
    }
	free(packets);
	// tell the incoming handler to prepare for packets
	sc_register_in_handler(inCB,con);
	// calc RTO for packet
	connection_get_rtt_estimate(con,&rtt,&mdev,&count);
	if(count==0)		// if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=rtt+2*mdev;
	else 
		rto= rtt+4*mdev;
	rto=MIN(rto,MAXRTO);
	// print info
	gettimeofday(&now,NULL);
	fprintf(tr->out,"%s -\tSending train=%d type=%s safettl=%d nProbes=%d payload=%d RR=%d rto=%ld(%ld) time=%ld.%.6ld\n", buf,tr->iteration, 
			ProbeString[tr->probeType], tr->safeTTL, tr->nProbes[tr->iteration],UseLightTrain?-1:payload,useRR,rto,count,now.tv_sec, (long)now.tv_usec);
	tr->probes[tr->iteration][0].timerID=sc_register_timer(timerCB_rpt,con,rto, (void *)tr->iteration);	// scheduled timeout in 1 RTO

}

/*********************************************************************
 * void idleCB_traceroute(struct connection * con)
 * 	this gets called when the monitored connection has no outstanding data
 * 	and tr->phase==PHASE_TR
 */

void idleCB_traceroute(struct connection * con)
{
	trdata *tr;
	// send a TTL=$TLL packet along connection
 	struct packet * p;
	struct iphdr ip;
	char buf[BUFLEN];
	int len = BUFLEN;
	long rtt,mdev,count,rto;
	struct timeval now;
	int ip_id;

	// get our per connection data
	tr = (trdata *) connection_get_app_data(con);
	assert(tr);
	// these tests should in independent of Depth Vs Breadth first
	if(tr->done)
		return;
	connection_get_name(con,buf,&len);
	switch(tr->probeType)
	{
		case SYNACK_PROBE:
		case FINACK_PROBE:
			p = connection_make_packet(con);	// get a default packet for this connection
			assert(p);
			// fill in with 1 byte of data (tiny gram)
			packet_fill_old_data(con,p,1);		// this will fill in SYN|ACK or FIN|ACK if approp
			break;
		case DATA_PROBE:
			assert(tr->lastDataPacket);
			p=packet_duplicate(tr->lastDataPacket);
			break;
		default:
			fprintf(stderr,"Unknown data probe type %d on connection %d\n",
					tr->probeType,tr->conId);
			abort();
	}
	assert(p);
	// frob the ip header
	packet_get_ip_header(p,&ip);
	ip.ttl=tr->nextTTL;
	ip.id=make_ip_id(tr,tr->iteration,tr->nextTTL,0);	
	tr->probes[tr->iteration][tr->nextTTL].status=PROBE_STATUS_SENT;
	tr->probes[tr->iteration][tr->nextTTL].matched=0;
	tr->probes[tr->iteration][tr->nextTTL].ttl=tr->nextTTL;
	tr->probes[tr->iteration][tr->nextTTL].type=PROBE_TR;

	packet_set_ip_header(p,&ip);
	// tell the incoming handler to prepare for packets
	sc_register_in_handler(inCB,con);
	// calc RTO for packet
	connection_get_rtt_estimate(con,&rtt,&mdev,&count);
	if(count==0)		// if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=rtt+2*mdev;
	else 
		rto= rtt+4*mdev;
	rto=MIN(rto,MAXRTO);
	// print info
	gettimeofday(&now,NULL);
	fprintf(tr->out,"%s -\tSending probe=%s phase=%d ttl=%d it=%d id=%d(%d) rto=%ld(%ld) time=%ld.%.6ld\n", buf, 
			ProbeString[tr->probeType], tr->phase, tr->nextTTL, tr->iteration,ntohs(ip.id), ip.id,
			rto,count,now.tv_sec, (long)now.tv_usec);
	// send packet
	packet_send(p);
	ip_id=ip.id;
	tr->probes[tr->iteration][tr->nextTTL].timerID=sc_register_timer(timerCB_traceroute,con,rto,
			(void *)ip_id);	// scheduled timeout in 1 RTO
	packet_free(p);
}
/**********************************************************************
 * void timerCB_rpt(struct connection * con)
 * 	A timer has gone off... we use this to determine when a probe is probably
 * 	not going to return; the arg is a cast int is the iteration # of the train
 */
void timerCB_rpt(struct connection * con,void *arg)
{
	trdata *tr;
	struct timeval now;
	int iteration;

	iteration = (int)arg;
	assert((iteration>=0)&&(iteration<Iterations));
	gettimeofday(&now,NULL);
	tr = (trdata *)connection_get_app_data(con);
	assert(tr);
	fprintf(tr->out,"- -	timeout on RPT %d	%d probes outstanding time=%ld.%.6ld\n",iteration,
			tr->nProbesOutstanding[iteration], now.tv_sec,(long)now.tv_usec);
	tr->probes[iteration][0].timerID=-1;	// mark the timer as handled
	// free all the probe state
	// probe_cache_flush(con);	// don't do this b/c it prevents us from tracking lost probes across trains
	calc_next_probe(con,tr,0,0);
	if(!tr->done)
	{
		if(tr->phase == PHASE_RPT)
			sc_register_idle(idleCB_rpt,con,IdleTime);	// idle timer to idletime
		else
			sc_register_idle(idleCB_traceroute,con,IdleTime);	// idle timer to idletime
	}
}
/**********************************************************************
 * void timerCB_traceroute(struct connection * con)
 * 	A timer has gone off... we use this to determine when a probe is probably
 * 	not going to return; the arg is a cast int is the ttl of the probe this timeout is for
 */
void timerCB_traceroute(struct connection * con,void *arg)
{
	trdata *tr;
	struct timeval now;
	int ttl, iteration, id,rpt;
	int err;

	id = (int)arg;
	tr = (trdata *)connection_get_app_data(con);
	assert(tr);
	err=convert_ip_id(tr,id,&iteration,&ttl,&rpt);
	assert(!err);
	assert(rpt==0);
	assert((ttl>0)&&(ttl<=MaxTTL));
	gettimeofday(&now,NULL);
	fprintf(tr->out,"- -	timeout TTL %d iteration=%d\t time=%ld.%.6ld\n",ttl, iteration,
			now.tv_sec,(long)now.tv_usec);
	tr->probes[iteration][ttl].timerID=-1;
	tr->probes[iteration][ttl].status=PROBE_STATUS_TIMEDOUT;
	calc_next_probe(con,tr,0,0);
	if(!tr->done)
	{
		if(tr->phase == PHASE_RPT)
			sc_register_idle(idleCB_rpt,con,IdleTime);	// idle timer to idletime
		else
			sc_register_idle(idleCB_traceroute,con,IdleTime);	// idle timer to idletime
	}
}
/***********************************************************************
 *  void timewaitCB(struct connection *con) 
 *  	this gets called when the other side goes into timewait, so we can
 *  	start doing FIN|ACK scans
 */
void timewaitCB(struct connection *con)	
{
	trdata *tr;
	char buf[BUFLEN];
	struct timeval now,diff;
	int len;

	assert(con);
	len = BUFLEN;
	connection_get_name(con,buf,&len);
	tr= connection_get_app_data(con);
	assert(tr);
	gettimeofday(&diff,NULL);
	now=diff;

	timersub(&now,&tr->starttime,&diff);
	fprintf(tr->out, "%s :: connection FIN closed: id = %d : time connected %ld.%.6ld time=%ld.%.6ld\n", 
			buf, connection_get_id(con),diff.tv_sec, (long)diff.tv_usec,
			now.tv_sec,(long)now.tv_usec);
	if(SkipFinAck)
	{
		fprintf(tr->out,"%s :: skipping FINACK probes; immediate close\n",buf);
		closeCB(con);
		return;
	}
	tr->probeType=FINACK_PROBE;		// now that the connection is closed, change to FIN|ACK probes
}

/***********************************************************************
 * void closeCB(struct connection * con)
 * 	this gets called when the connection is no longer usable, which means
 * 	1) either local or remote sent a RST
 * 	2) local initiated the connection close
 */
void closeCB(struct connection * con)	
{
	trdata *tr;
	struct timeval now,diff;
	char buf[BUFLEN];
	int len;
	char * finished;

	tr= connection_get_app_data(con);
	if(tr==NULL)	// this connection is already done; just return
		return;
	gettimeofday(&now,NULL);
	/*
	diff=now;
	if(diff.tv_usec<tr->starttime.tv_usec)
	{
		diff.tv_sec--;
		diff.tv_usec+=1000000;
	}
	diff.tv_sec-=tr->starttime.tv_sec;
	diff.tv_usec-=tr->starttime.tv_usec;
	*/
	timersub(&now,&tr->starttime,&diff);
	len=BUFLEN;
	if(tr->done)
		finished="DONE";
	else 
		finished="INCOMPLETE";

	connection_get_name(con,buf,&len);
	fprintf(tr->out,"%s :: finished=%s connection destroyed alive=%ld.%.6ld at time=%ld.%.6ld\n",
			buf,finished,diff.tv_sec,(long)diff.tv_usec,now.tv_sec,(long)now.tv_usec);
	connection_set_app_data(con,NULL);	// zero it out
	if(tr->forceCloseID!=-1)		// cancel forceClose timer
	{
		sc_cancel_timer(con,tr->forceCloseID);
		tr->forceCloseID=-1;
	}
	sc_register_idle(NULL,con,-1);		// turn off idle timer
	// make sure no one calls us again
	sc_register_icmp_in_handler(NULL,con);
	sc_register_in_handler(NULL,con);
	sc_register_out_handler(NULL,con);
	sc_register_timewait(NULL,con);
	sc_register_close(NULL,con);

	trdata_free(tr);	// free the resources
}

/*****************************************************************************
 * void forceCloseCB(struct connection * con)
 * 	this is called when the connection has been persistant for too long
 * 	it basically means that the connection should have been closed, but wasn't for
 * 	some reason or another
 */

void forceCloseCB(struct connection * con, void * arg)
{
	trdata *tr;
	char buf[BUFLEN];
	int len=BUFLEN;
	struct timeval diff;
	sc_register_close(NULL,con);
	tr= connection_get_app_data(con);
	if(tr==NULL)    // this connection is already done; just return
		return;
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
	fprintf(tr->out,"%s ForceClosing Connection!! done :: %ld.%.6ld\n",buf,diff.tv_sec,(long)diff.tv_usec);
	sc_register_idle(NULL,con,-1);		// turn off any idle timer
	tr->forceCloseID=-1;			// mark the force close timer as handled
	closeCB(con);
	connection_force_close(con);		// HACK: tell sidecar to drop state for this connection	
}
