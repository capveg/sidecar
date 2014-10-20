#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netinet/udp.h>
#include <netdb.h>


#include <sys/types.h>
#include <sys/socket.h>

#include <pcap.h>

#include <math.h>

#include "log.h"
#include "wc_event.h"
#include "utils.h"
#include "pcapstuff.h"
#include "pmdb.h"
#include "pmdb_ipcache.h"


// Slapdash hacks

int ProbeRate=200*1024;	// 20KB/s
int ProbeSize=40;	// bytes
unsigned short Port=0;
int SourceSock=-1;
double SendTimeout = 1;	// one second timeout, by default
struct wc_queue * Events;
pmdb * Ip2Probes;


#ifndef BUFLEN
#define BUFLEN 4096
#endif

// Prototypes

typedef struct probe 
{
	u_int32_t dstIp;
	u_int16_t dstPort;
	int times;
	double interProbeTime;
	struct timeval sendtime;
} probe;

probe * make_probe(char * host,int port,int times,double interProbeTime);
int event_loop(pcap_t * handle, struct wc_queue * events,pcap_handler callback);
pcap_t *  seed_events(struct wc_queue * events, int argc, char * argv[]);
void handle_packet(u_char *, const struct pcap_pkthdr *, const u_char *);
void sendUDPProbe(void * probePtr);



/****************************************************************
 * main()
 * 	throw all the work into seed_events and event_loop
 */

int main(int argc, char * argv[])
{
	
	pcap_t * handle;
	struct wc_queue * events = wc_queue_init(10);		// 10 == initial size; will grow 
							// so it doesn't matter
	Events=events;			// LAME!
	Ip2Probes=pmdb_create(PMDB_IPCACHE_HASHSIZE,pmdb_ipcache_hash,pmdb_ipcache_cmp,NULL); // Poor Man's DataBase
	handle = seed_events(events,argc,argv);
	return event_loop(handle, events,handle_packet);
}


/*******************************************************************
 * int event_loop(int pcap_fd, wc_queue * events)
 * 	while(events queue not empty)
 * 		1) find time to next event() == delta
 *		2) select() on pcap with time	delta
 *		3) if you get a packet, pass it to handle packet
 *		4) if you timeout on select, run event
 */

int event_loop(pcap_t * handle, struct wc_queue * events, pcap_handler callback)
{
	int queueStatus;
	int pcap_fd;
	struct timeval delta;
	fd_set readfds;
	int err;

	pcap_fd = pcap_fileno(handle);
	sidecarlog(LOGDEBUG,"Entering Event Loop\n");
	while(1)	// we break out of this loop in other ways
	{
		while((queueStatus=wc_get_next_event_delta(events,&delta))==1)
			wc_run_next_event(events);	// flush all the events that have passed
		if(queueStatus==-1)	// if queue is empty
			break;		// drop out of the loop
		// setup bits for select()
		FD_ZERO(&readfds);
		FD_SET(pcap_fd,&readfds);
		// run select
		err=select(pcap_fd+1, &readfds,NULL,NULL,&delta);
		if(err==0)
			continue;		// we timed out; jump to top of loop to run event
		if((err==-1)&&(errno==EINTR))   // we has a system call interrupt us
			continue;               //      just move on
		if(err<0)			// select() died :-(
		{
			perror("select");       // FIXME : more graceful?
			abort();
		}
		// if we got here, then we must have a packet to read!
		assert(FD_ISSET(pcap_fd,&readfds));		// make sure we're not smoking crack
		while((err=pcap_dispatch(handle,1,callback,(u_char*)events))>0);	// grab all packets
		if(err<0)
		{
			sidecarlog(LOGCRIT,"pcap_dispatch returned %d :: %s\n",
					err,pcap_geterr(handle));
		}
	}
	sidecarlog(LOGDEBUG,"Exiting Event Loop\n");

	return 0;
}

/************************************************************************
 * int seed_events(wc_queue * events, int argc, char * argv[]);
 * 	init() pcap filter and handle
 * 	parse args and decide what to put on the event queue
 * 	return pcap handle
 */

pcap_t *  seed_events(struct wc_queue * events, int argc, char * argv[])
{
	pcap_t * handle;
	char filterStr[BUFLEN];
	char localIPBuf[BUFLEN];
	unsigned int localIP;
	struct sockaddr_in sa;
	unsigned int len;
	struct timeval now;
	probe * p;
	


	sc_setlogflags(LOGCRIT|LOGINFO|LOGDEBUG2);
	sc_setlogflags(LOGCRIT|LOGINFO);
	SourceSock = socket(PF_INET,SOCK_DGRAM,0);
	if( SourceSock <=0)
	{
		perror("socket");
		abort();
	}

	// bind an arbitary socket to reserve for our use
	sa.sin_port=INADDR_ANY;
	sa.sin_addr.s_addr=INADDR_ANY;
	sa.sin_family=AF_INET;
	if(bind(SourceSock,(struct sockaddr *) &sa, sizeof(sa)))
	{
		perror("bind");
		abort();
	}
	// now figure out what port we got
	len = sizeof(sa);
	if(getsockname(SourceSock,(struct sockaddr *) &sa, &len))
	{
		perror("getsockname");
		abort();
	}
	sidecarlog(LOGINFO,"Sending packets out on port: %u\n",ntohs(sa.sin_port));
	Port = ntohs(sa.sin_port);

	localIP=getLocalIP();
	inet_ntop(AF_INET,&localIP,localIPBuf,32);
	snprintf(filterStr,BUFLEN,"icmp and dst host %s",localIPBuf);
	handle = pcap_init(filterStr,NULL);
	//p = make_probe("129.143.101.41",33433,10,1.0);
	p = make_probe("87.119.78.1",33433,10,2.0);
	gettimeofday(&now,NULL);
	wc_event_add(events,sendUDPProbe,p,now);	// 10 times, 1/second
	return handle;
}
/******************************************************************************
 * void scheduleNextProbe(probe * p, int id)
 * 	read the probe info, and schedule the next time
 * 	we should probe this IP.  
 * 	Use how fast the ip id is going to determine it
 */

void scheduleNextProbe(probe * p, int id)
{
	assert(p);
	struct timeval t;
	if(p->times>0)
	{
		t= p->sendtime;
		p->times--;
		t.tv_sec+=(int)ceil(p->interProbeTime);
		t.tv_usec+=100000*(p->interProbeTime-ceil(p->interProbeTime));
		wc_event_add(Events,sendUDPProbe,p,t);
	}
}

/*******************************************************************************
 * void probetimeout(void * probePrt)
 * 	print a timeout message
 * 	schedule next probe	(if necessary)
 */

void probetimeout(void * probePtr)
{
	probe * p = (probe *) probePtr;
	char dstbuf[BUFLEN];
	inet_ntop(AF_INET,&p->dstIp,dstbuf,BUFLEN);
	fprintf(stdout,"%16s %16s - - - %12s\n" ,
			dstbuf,
			"-",
			"-");
	scheduleNextProbe(p,-1);
}


/*******************************************************************************
 * 	void sendUDPProbe(void * probePtr)
 * 		send a UDP probe to the ip/port in the probe struct
 */

void sendUDPProbe(void * probePtr)
{
	probe * p = (probe *) probePtr;
	static char data[12];		// 12 == amount of data to make this a 40 byte mesg
	static int needInit=1;
	struct sockaddr_in dst;
	char strBuf[32];
	int err;
	struct timeval now;

	if(needInit)
	{
		needInit=0;
		memset(data,0,12);
	}
	dst.sin_family=AF_INET;
	dst.sin_addr.s_addr = p->dstIp;
	dst.sin_port = htons(p->dstPort);
	err= sendto(SourceSock,data,12,0,(struct sockaddr *) & dst, sizeof(dst));
	if(err<12)
	{
		sidecarlog(LOGINFO,"sendto(%s,%u) return %d instead of 12)",
				inet_ntop(AF_INET,&p->dstIp,strBuf,32),
				p->dstPort,
				err);
		if(err<0)
		{
			perror("sendto");
		}
	}
	gettimeofday(&now,NULL);
	p->sendtime=now;
	now.tv_sec+=SendTimeout;
	wc_event_add(Events,probetimeout,p,now);

}


/*******************************************************************************
 * int handle_packet(u_char *arg, const struct pcap_pkthdr *pcaph, const u_char *data);
 *	when we get a callback from pcap, it comes here
 */

void handle_packet(u_char *arg, const struct pcap_pkthdr *pcaph, const u_char *data)
{
	struct iphdr *ip;
	struct iphdr *bounce_ip;
	struct udphdr *udp;
	struct icmphdr * icmp;
	char srcbuf[BUFLEN];
	char dstbuf[BUFLEN];
	char bouncedst[BUFLEN];
	int offset;
	probe *p;
	void * key;


	assert((pcaph->caplen)>(14+sizeof(struct iphdr)));   // dirty check for runt packets
	// we've already asserted we're on ethernet in pcapinit(), so we can skip ahead 14 bytes
	offset=14;
	ip=(struct iphdr *)&data[offset];
	inet_ntop(AF_INET,&ip->saddr,srcbuf,BUFLEN);
	inet_ntop(AF_INET,&ip->daddr,dstbuf,BUFLEN);
	if(ip->protocol != IPPROTO_ICMP)
	{
		sidecarlog(LOGINFO,"Weird; got non-icmp packet: %s -> %s : proto %d; skipping\n",
				srcbuf,dstbuf,ip->protocol);
		return;
	}
	// must be ICMP to get to here
	offset += ip->ihl*4;
	if(offset+sizeof(struct icmphdr)> pcaph->caplen)
	{
		sidecarlog(LOGINFO,"Ignoring short icmp packet: %s -> %s : %d > %d \n",
				srcbuf,dstbuf,
				offset+sizeof(struct icmphdr), 
				pcaph->caplen);
		return;
	}
	icmp = (struct icmphdr *) &data[offset];	// offset to icmp structure
	if(icmp->type != ICMP_DEST_UNREACH || icmp->code != ICMP_PORT_UNREACH)
	{
		sidecarlog(LOGDEBUG,"Ignoring non-PORT-UNREACH icmp: %s -> %s : type %d code %d \n",
				srcbuf,dstbuf, icmp->type, icmp->code);
		return;
	}
	offset+= 8;		// length of the PORT-UNREACH icmp header
	bounce_ip = (struct iphdr *) &data[offset];	// offset into the bounced packet's ip header
	offset+=bounce_ip->ihl*4;
	udp = (struct udphdr *) &data[offset];	// offset into bounced udp (partial) header; only 8 bytes are valid
	if(udp->source != htons(Port))
	{
		sidecarlog(LOGDEBUG,"Ignoring PORT-UNREACH icmp from wrong port: %s -> %s : port %d != %d \n",
				srcbuf,dstbuf, ntohs(udp->source),Port);
		return;

	}
	inet_ntop(AF_INET,&bounce_ip->daddr,bouncedst,BUFLEN);
	fprintf(stdout,"%16s %16s %ld.%.6ld %d %d %12s\n" ,
			bouncedst,
			srcbuf,
			pcaph->ts.tv_sec,
			pcaph->ts.tv_usec,
			ntohs(ip->id),
			ip->id,		// assumes localhost is little endian
			"Icmp_t=3,c=3");
	key = pmdb_ipcache_ip2data(bounce_ip->daddr);
	p = (probe *) pmdb_lookup(Ip2Probes,key);
	if(p == NULL)
	{	
		sidecarlog(LOGCRIT,"Couldn't find IP->Probe mapping for %s; giving up \n", bouncedst);
		return;
	}
	scheduleNextProbe(p,ntohs(ip->id));
}
/********************************************************************************
 *	probe * make_probe(char * host,int port);
 *		return a probe structure with host and port filled in
 */
probe * make_probe(char * host,int port,int times, double interProbe)
{
	probe * p;
	struct addrinfo *ai;
	struct sockaddr_in *sa;
	void * key;


	if(getaddrinfo(host,NULL,NULL,&ai))
		return NULL;
	p = malloc(sizeof(probe));
	assert(p);
	p->dstPort=port;
	sa = (struct sockaddr_in * )ai->ai_addr;
	p->dstIp = sa->sin_addr.s_addr;
	freeaddrinfo(ai);
	p->times=times;
	p->interProbeTime=interProbe;
	key = pmdb_ipcache_ip2data(p->dstIp);
	pmdb_insert(Ip2Probes,key,p);
	// free(key);		// don't free key here --- it's still in use
	return p;
}
