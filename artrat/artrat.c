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

#include "sidecar.h"
#include "artrat.h"
#include "diffs.h"
#include "netutils.h"


char * Dev=NULL;		// use pcap default
int LogLevel=LOGCRIT;		// only log crit by default
float ProbesPerSecond=20.0;
int ICMPTTL=5;			// TTL on init ICMP probes (how deep into network)
int NProbes=5;			// Number of ICMP probes in a burst/round
int CompareType=5;
int AlternatingOptions=0;
int OneShot=0;
char * OneShotTarget=NULL;
int OneShotPort=80;
int OneShotSock=-1;
int OneShotMSTime=15*1000;	// 15s 
int TestTSType3=0;
u32 Type3Targets[9];
int NType3Targets=0;


// protos
int parse_args(int argc, char * argv[]);
void usage(char *s1, char *s2);
artratcon * artratcon_new();
int artratcon_free(artratcon *);

void schedule_next_probe(struct connection * con);
void schedule_next_icmp_probe(struct connection * con);

void artrat_connectionCB(struct connection *);
void artrat_closeCB(struct connection *);
void artrat_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void artrat_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void artrat_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void artrat_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void artrat_sendprobe(struct connection *,void*);
void artrat_send_icmp_probe(struct connection *,void*);
void artrat_send_init_icmp_probe(struct connection *);
void artrat_timeout(struct connection *,void*);
void artrat_icmp_timeout(struct connection *,void*);
void artrat_initCB(void *);
void artrat_end_oneshot(struct connection *, void *);

void newrtt(artratcon *,struct timeval);


/**************
 * main():
 * 	parse_args, setup sidecar, then hand control to sidecar
 */


int main(int argc, char * argv[])
{
	char buf[BUFLEN];
	int i;

	i=parse_args(argc, argv);
	buf[0]=0;
	if(!OneShot)
	{
		for(;i<argc;i++)
		{
			strncat(buf,argv[i],BUFLEN);
			strncat(buf," ",BUFLEN);
		}
	}
	else
	{
		snprintf(buf,BUFLEN,"tcp and host %s and port %d",OneShotTarget, OneShotPort);
	}
	fprintf(stderr,"Setting pcap filter to '%s'\n",buf);
	// set log level
	sc_setlogflags(LogLevel);
	// tell sidecar to watch that stream
	sc_init(buf,Dev,0);
	sc_set_max_mem(100*1024*1024);	// impossibly large limit, for debugging w/valgrind
	// register callbacks with sidecar
	sc_register_connect(artrat_connectionCB);	// when we get a new connection
	if(OneShot)
		sc_register_init(artrat_initCB,NULL);	// connect to OneShotTarget here
	sc_do_loop();					// hand control to sidecar

	return 0;
}


/***************************************************************************
 * void artrat_initCB(void *);
 * 	connect to OneShotTarget 
 */

void artrat_initCB(void *ignore)
{
	assert(OneShot);	// should only be called in OneShot mode
	OneShotSock = make_tcp_connection(OneShotTarget,OneShotPort,3000);	// 3s timeout
	if(OneShotSock==-1)
	{
		perror("make_tcp_connection():");
		exit(1);
	}
}


/***********************************************************************
 * void schedule_next_probe()
 * 	schedules the next rtt probe, unless we have sent too many
 */

void schedule_next_probe(struct connection * con)
{
	long uswait = (double)1000000/ProbesPerSecond;
	artratcon * ac;

	ac=(artratcon*)connection_get_app_data(con);
	ac->ProbeID++;
	if(ac->ProbeID>0xffff)					// must fit in 16 bits
		ac->ProbeID=0;
	ac->ProbeCount++;
	ac->ProbeTimestamp.tv_sec=ac->ProbeTimestamp.tv_usec = 0;	// mark this as uninitialized
	sc_register_timer(artrat_sendprobe,con,uswait,NULL);	// start the probe timer
}

/***********************************************************************
 * void schedule_next_icmp_probe()
 * 	schedules the next probe, unless we have sent too many
 */

void schedule_next_icmp_probe(struct connection * con)
{
	long uswait = (double)1000000/ProbesPerSecond;
	artratcon * ac;

	ac=(artratcon*)connection_get_app_data(con);
	ac->ICMPProbeCount++;
	assert(ac->nIcmpProbesOutstanding==0);
	sidecarlog(LOGAPP,"NEXT icmp in %ld us\n",uswait);	
	sc_register_timer(artrat_send_icmp_probe,con,uswait,NULL);	// start the probe timer
}
/***********************************************************************
 * void artrat_connectionCB(struct connection *);
 * 	gets called when connection is completed
 * 	- start the sendprobe timer
 */

void artrat_connectionCB(struct connection *con)
{
	char buf[BUFLEN];
	int len=BUFLEN;

	artratcon * ac;

	connection_get_name(con,buf,&len);
	sidecarlog(LOGAPP,"got new connectionCB:: %s\n",buf);
	sc_register_close(artrat_closeCB,con);			// when to stop
	sc_register_in_handler(artrat_in_handler,con);		// tells us when to recv()
	sc_register_out_handler(artrat_out_handler,con);	// needed to timestamping outgoing packets
	sc_register_icmp_out_handler(artrat_icmp_out_handler,con);// needed to timestamping outgoing packets
	sc_register_icmp_in_handler(artrat_icmp_in_handler,con);
	// start ProbeID as half way through the sequence space
	ac = artratcon_new();
	assert(ac);
	ac->ProbeID=(connection_get_ip_id(con)+0x7ffff)&0xffff;
	ac->icmpIpId=(connection_get_ip_id(con)+0x7f000)&0xffff;
	connection_set_app_data(con,ac);
	schedule_next_probe(con);
	schedule_next_icmp_probe(con);
	if(OneShot)
		sc_register_timer(artrat_end_oneshot,con,OneShotMSTime*1000, NULL);
}

/*************************************************************************
 * void artrat_closeCB(struct connection *);
 * 	connection is closed; shutdown sidecar
 */

void artrat_closeCB(struct connection *con)
{
	artratcon * ac;
	char buf[BUFLEN];
	int len=BUFLEN;
	int i;

	connection_get_name(con,buf,&len);
	ac=(artratcon *)connection_get_app_data(con);
	printf("CLOCKPRE: ");
	for(i=0;i<ac->nStamps;i++)
	{
		printf("%d:%d ",i,ac->clockprecision[i]); 
	}
	printf("\n");
	if(ac)
		artratcon_free(ac);
	connection_set_app_data(con,NULL);
	sidecarlog(LOGAPP,"got closeCB:: %s\n",buf);
	if(OneShot)
		exit(0);
}

/**************************************************************************
 * void artrat_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *	Got an incoming packet; if it's a redundant ack output time delta to stdout, else
 *	output data to stderr (unless webrequest is set)
 */

void artrat_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct timeval diff;
	struct iphdr ip;
	artratcon *ac;
	ac=(artratcon *)connection_get_app_data(con);
	if(packet_is_redundant_ack(p,con))
	{
		sidecarlog(LOGAPP,"got redundant ack\n");
		// got Probe response
		packet_get_ip_header(p,&ip);
		if(ac->ProbeOutstanding!=1)
		{
			sidecarlog(LOGAPP,"Got response to unknown probe: id=%u(%u)\n",
					ntohs(ip.id),ip.id);
			assert(ac->TimeoutID==-1);		// should never have a timer going without a probe outstanding
			return;
		}
		ac->ProbeOutstanding=0;
		if(ac->TimeoutID !=-1)
			sc_cancel_timer(con,ac->TimeoutID);
		ac->TimeoutID=-1;
		// 64 bytes from www.cs.umd.edu (128.8.128.160): icmp_seq=0 ttl=241 time=15.0 ms
		// fprintf(stdout,"%d bytes from %s (%s): tcp_seq=%d(%d) ttl=%d ",
		// 		ntohs(ip.tot_len),TargetHost,TargetHostIp,ProbeCount,ntohs(ip.id),ip.ttl);
		if(!(ac->ProbeTimestamp.tv_sec==0 && ac->ProbeTimestamp.tv_usec == 0))
		{
			timersub(&phdr->ts,&ac->ProbeTimestamp,&diff);	// calc delta
			// fprintf(stdout,"time=%s",prettyTime(diff,buf,BUFLEN));
			newrtt(ac,diff);
		}
		// fprintf(stdout," now=%ld.%.6ld s\n",phdr->ts.tv_sec,phdr->ts.tv_usec);
		schedule_next_probe(con);
	}
	// else ignore; is incoming application data
}

/***************************************************************************
 *  void artrat_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *  	if this packet matches our current ProbeID, record the time
 */

void artrat_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	artratcon *ac;
	packet_get_ip_header(p,&ip);
	ac=(artratcon *)connection_get_app_data(con);
	if(!ac->ProbeOutstanding)
		return;
	if(ip.id != htons(ac->ProbeID))
		return;
	// this is out outgoing probe packet; record time
	ac->ProbeTimestamp = phdr->ts;
}
/***************************************************************************
 *  void artrat_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *  	if this packet matches our icmp probe, then record the send time
 */

void artrat_icmp_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct icmp_header icmp;
	int id;
	aprobe * ap;
	packet_get_icmp_header(p,&icmp);
	if(ntohs(icmp.un.echo.id)!=getpid())
		return;		// we didn't send this packet
	id = ntohs(icmp.un.echo.sequence);
	ap = (aprobe *) probe_lookup(con,id);
	if(!ap)
	{
		sidecarlog(LOGAPP,"tried to timestamp unknown outgoing icmp packet: %d (%d)\n",
				ntohs(icmp.un.echo.sequence),icmp.un.echo.sequence);
		return;
	}
	// this is out outgoing probe packet; record time
	ap->sent = phdr->ts;
}

/*****************************************************************************************
 * void artrat_sendprobe(struct connection *,void*);
 * 	create and send probe packet; schedule timeout
 */

void artrat_sendprobe(struct connection * con,void* ignore)
{
	struct packet * probe;
	long rto;
	struct iphdr ip;
	char buf[BUFLEN];
	artratcon *ac;

	ac = (artratcon *) connection_get_app_data(con);
	probe = connection_make_packet(con);
	memset(buf,0,BUFLEN);
	packet_get_ip_header(probe,&ip);
	// use TCP; common case
	packet_fill_old_data(con,probe,1);		// this fills with the min data to solicit an ACK
	ip.id=htons(ac->ProbeID);
	packet_set_ip_header(probe,&ip);
	sidecarlog(LOGAPP,"Sending new tcprtt probe: %d \n",ac->ProbeCount);
	ac->ProbeOutstanding=1;
	packet_send(probe);
	// calc RTO for packet
	// connection_get_rtt_estimate(con,&rtt,&mdev,&count);	// don't use; includes delayed sack time
	if((ac->ProbeCount-ac->DropCount)<1)            // if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=2*ac->usVJRtt;
	else
		rto= ac->usVJRtt+4*ac->usVJMdev;
	sidecarlog(LOGAPP," scheduling timeout for tcp_seq=%d for %ld us\n",
			ac->ProbeCount,rto);
	ac->TimeoutID=sc_register_timer(artrat_timeout,con,rto,NULL);		// schedule timeout
}

/*****************************************************************************************
 * void artrat_send_icmp_probe(struct connection *,void*);
 * 	create and send icmp probe packet; schedule timeout
 */

void artrat_send_icmp_probe(struct connection * con,void* ignore)
{
	struct packet * probe;
	long rto;
	struct iphdr ip;
	struct icmp_header icmp;
	char buf[BUFLEN];
	char options[IP_MAX_OPTLEN];
	int optlen=IP_MAX_OPTLEN;
	artratcon *ac;
	int i;


	ac = (artratcon *) connection_get_app_data(con);
	if(ac->ICMPTargetValid==0)	// need to find a target first
		return artrat_send_init_icmp_probe(con);
	probe = connection_make_packet(con);
	memset(buf,0,BUFLEN);
	packet_get_ip_header(probe,&ip);
	// use ICMP; for comparison to TCP
	icmp.type=ICMP_ECHO;
	icmp.code=0;
	icmp.checksum=0;                // will get set at send
	packet_set_icmp_header(probe,&icmp);
	ip.protocol=IPPROTO_ICMP;
	ip.daddr = ac->ICMPTarget;			// send to router 5 hops in
	// ip.ttl=ICMPTTL;		// used for debugging
	packet_set_ip_header(probe,&ip);
	sidecarlog(LOGAPP,"Sending icmp echo packet train: %d \n",ac->ICMPProbeCount);
	// setup ip options
	memset(options,0,IP_MAX_OPTLEN);
	if(!TestTSType3)
	{
		options[0]=68;			// IP_OPTION_TS
		options[1]=IP_MAX_OPTLEN;	// length
		options[2]=5;			// pointer; point to first entry
		// options[3]=1;		// timestamps+ips
		options[3]=0;			// timestamps only
		optlen=IP_MAX_OPTLEN;
	}
	else
	{
		optlen=36;
		options[0]=68;			// IP_OPTION_TS
		options[1]=optlen;	// length
		options[2]=5;			// pointer; point to first entry
		options[3]=3;			// prescribed timestamps
		for(i=0;i<MIN(NType3Targets,4);i++)		// copy addresses into place
			memcpy(&options[i*8+4],&Type3Targets[i],sizeof(u32));
	}
	ac->nIcmpProbesOutstanding=0;
	for(i=0;i<ac->nIcmpProbes;i++)	// sent out ac->nIcmpProbes different probes
	{
		ip.id=htons(ac->icmpIpId++);
		packet_set_ip_header(probe,&ip);
		packet_tag_icmp_ping_with_connection(probe,con);     // this helps sidecar demux on connections
		packet_get_icmp_header(probe,&icmp);
		ac->icmpprobes[i]->seq = ntohs(icmp.un.echo.sequence);
		ac->icmpprobes[i]->status = PROBE_SENT;
		memset(&ac->icmpprobes[i]->sent,0,sizeof(struct timeval));
		probe_add(con,ac->icmpprobes[i]->seq,ac->icmpprobes[i]);
		if(AlternatingOptions && i%2)
		{
			packet_set_ip_options(probe,NULL,0);
			packet_set_data(probe,options,IP_MAX_OPTLEN);		// make sure packets are same size as options packets
		}
		else	
		{
			packet_set_ip_options(probe,options,optlen);	// set timestamp options 
			packet_set_data(probe,NULL,0);				// make sure the data is empty
		}
		memset(ac->icmpprobes[i]->options,0,IP_MAX_OPTLEN);	// zero the ip options
		packet_send(packet_duplicate(probe));
		ac->nIcmpProbesOutstanding++;
	}
	// calc RTO for packet
	// connection_get_rtt_estimate(con,&rtt,&mdev,&count);	// don't use; includes delayed sack time
	if((ac->ProbeCount-ac->DropCount)<1)     // if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=2*ac->usVJRtt;
	else
		rto= ac->usVJRtt+4*ac->usVJMdev;
	sidecarlog(LOGAPP," scheduling timeout for icmp_seq=%d for %ld us\n",
			ac->ICMPProbeCount,rto);
	ac->ICMPTimeoutID=sc_register_timer(artrat_icmp_timeout,con,rto,NULL);		// schedule timeout
	packet_free(probe);		// we made duplicates of everything
}


/*****************************************************************************************
 * void artrat_send_init_icmp_probe(struct connection *);
 * 	create and send icmp probe packet; schedule timeout
 * 	this one is ttl limited so that we can get the address of the
 * 	5th hop out
 */

void artrat_send_init_icmp_probe(struct connection * con)
{
	struct packet * probe;
	long rto;
	struct iphdr ip;
	struct icmp_header icmp;
	char buf[BUFLEN];
	artratcon *ac;
	char options[IP_MAX_OPTLEN];


	ac = (artratcon *) connection_get_app_data(con);
	probe = connection_make_packet(con);
	memset(buf,0,BUFLEN);
	packet_get_ip_header(probe,&ip);
	// use ICMP; for comparison to TCP
	icmp.type=ICMP_ECHO;
	icmp.code=0;
	icmp.checksum=0;                // will get set at send
	packet_set_icmp_header(probe,&icmp);
	packet_tag_icmp_ping_with_connection(probe,con);     // this helps sidecar demux on connections
	ip.protocol=IPPROTO_ICMP;
	
	ip.id=htons(ac->icmpIpId++);
	ip.ttl=ICMPTTL;
	packet_set_ip_header(probe,&ip);
	sidecarlog(LOGAPP,"Sending init icmp probe: %d :: ttl=%d\n",ac->ProbeCount,ICMPTTL);
	// set RR ip options for init probe
	memset(options,0,IP_MAX_OPTLEN);
	options[0]=0x01;		// NOOP
	options[1]=0x07;		// RR ip option
	options[2]=IP_MAX_OPTLEN-1;
	options[3]=4;		// first pointer
	packet_set_ip_options(probe,options,IP_MAX_OPTLEN);
	assert(ac->nIcmpProbes>=1);
	packet_get_icmp_header(probe,&icmp);
	ac->icmpprobes[0]->seq=ntohs(icmp.un.echo.sequence);
	ac->icmpprobes[0]->status=PROBE_SENT;
	probe_add(con,ac->icmpprobes[0]->seq,ac->icmpprobes[0]);
	memset(&ac->icmpprobes[0]->sent,0,sizeof(ac->icmpprobes[0]->sent));
	ac->nIcmpProbesOutstanding=1;
	packet_send(probe);
	// calc RTO for packet
	if((ac->ProbeCount-ac->DropCount)<1)     // if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=ac->usVJRtt+2*ac->usVJMdev;
	else
		rto= ac->usVJRtt+4*ac->usVJMdev;
	sidecarlog(LOGAPP," scheduling timeout for tcp_seq=%d for %ld us\n",
			ac->ProbeCount,rto);
	ac->ICMPTimeoutID=sc_register_timer(artrat_icmp_timeout,con,rto,NULL);		// schedule timeout
}

/**************************************************************************************8
 * void artrat_timer(struct connection *,void*)
 * 	register the timeout, print and reschule next probe
 */

void artrat_timeout(struct connection *con,void*ignore)
{
	artratcon *ac;
	ac = (artratcon *)connection_get_app_data(con);
	ac->ProbeOutstanding=0;
	ac->DropCount++;
	ac->TimeoutID=-1;
	schedule_next_probe(con);
}

/**************************************************************************************8
 * void artrat_icmp_timer(struct connection *,void*)
 * 	register the timeout, print and reschule next probe
 */

void artrat_icmp_timeout(struct connection *con,void*ignore)
{
	artratcon *ac;
	ac = (artratcon *)connection_get_app_data(con);
	ac->ICMPDropCount+=ac->nIcmpProbesOutstanding;
	ac->nIcmpProbesOutstanding=0;
	diffPacketProbes(ac);
	ac->ICMPTimeoutID=-1;
	probe_cache_flush(con);		// remove lingering state
	schedule_next_icmp_probe(con);
}

/**************************************************************************************
 *  void parse_args(int argc, char * argv[]);
 *  	parse arguments :: add some actual arg parsing here
 */

int parse_args(int argc, char * argv[])
{
	int c;
	 while((c=getopt(argc,argv,"3:c:d:i:n:oO:p:r:t:"))!=EOF)
	 {
		switch(c)
		{
			case '3':
				TestTSType3=1;
				inet_pton(AF_INET,optarg,&Type3Targets[NType3Targets]);
				NType3Targets++;
				CompareType=3;		// type 3 parsing on return
				break;
			case 'c':
				CompareType=atoi(optarg);
				break;
			case 'd':
				LogLevel=atoi(optarg);
				break;
			case 'i':
				Dev=strdup(optarg);
				break;
			case 'n':
				NProbes=atoi(optarg);
				break;
			case 'o':
				AlternatingOptions=1;
				break;
			case 'O':
				OneShot=1;
				OneShotTarget=strdup(optarg);
				break;
			case 'p':
				OneShotPort=atoi(optarg);
				break;
			case 'r':
				ProbesPerSecond=atof(optarg);
				break;
			case 't':
				ICMPTTL=atoi(optarg);
				break;
			default:
				usage("unknown option",argv[optind]);
				break;
		}
	 }
	 return optind;
}

/*************************************************************************************
 * void usage(char *s1, char *s2);
 * 	print usage message, the error strings and quit
 */

void usage(char * s1, char * s2)
{
	if(s1)
		fprintf(stderr,"%s",s1);
	if(s2)
		fprintf(stderr," %s",s2);
	if(s1||s2)
		fprintf(stderr,"\n");
	fprintf(stderr,"Usage::\n"
			"artrat [options] <pcap_filter_str> [pcap_filter_str...]\n\n"
			"\t-3 ip -- test timestamps type 3 on ip(specify addresses)\n"
			"\t-c comparetype	[%d]\n"
			"\t-d debuglevel	[%d]\n"
			"\t-i dev 		[auto]\n"
			"\t-n nprobes 	[%d]\n"
			"\t-o  -- set ip options only for even probes\n"
			"\t-O  target -- OneShot mode: connect to target and quit\n"
			"\t-p port	[%d] OneShot port\n"
			"\t-r nProbes/s	[%f] (takes floats)\n"
			"\t-t ttl		[%d] ttl for init ICMP probes (how deep into network)\n"
			"\t\n\n\n\n"
			"i.e, ./artrat -r 1.5 -i eth1 port 80\n",
			CompareType,
			LogLevel,
			NProbes,
			OneShotPort,
			ProbesPerSecond,
			ICMPTTL);
	exit(2);
}
 
/**********************************************************************************
 * void newrtt(struct timeval rtt);
 * 	we have a new data point for rtts, update statistics
 */

void newrtt(artratcon *ac, struct timeval rtt_tv)
{
	long rtt_est;
	long err;

	rtt_est = 1000000l*rtt_tv.tv_sec+rtt_tv.tv_usec;
	if(rtt_est<ac->usBaseRtt)
		ac->usBaseRtt=rtt_est;
	
	// VJ's three magic lines
	err = rtt_est - ac->usVJRtt;
	if(ac->usVJRtt)		// if this is not our first sample
		ac->usVJRtt +=(err>>3);
	else		
		ac->usVJRtt=err; // if this is our first sample (converges faster)
	ac->usVJMdev+= (labs(err)-ac->usVJMdev)>>2;  // labs() == abs() for longs, who knew?
	ac->usLastRtt = rtt_est;
}


/****************************************************************************************
 * void artrat_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 * 	if this is an echo reply, then lookup time and print
 */

void artrat_icmp_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	struct icmp_header icmp;
	artratcon * ac;
	int len;
	u16 id;
	aprobe *ap;

	len=IP_MAX_OPTLEN;
	sidecarlog(LOGAPP,"got icmp in CB\n");
	ac = (artratcon *) connection_get_app_data(con);
	// got Probe response
	packet_get_ip_header(p,&ip);
	packet_get_icmp_header(p,&icmp);
	if(icmp.type== ICMP_TIME_EXCEEDED)
	{
		if((ac->nIcmpProbesOutstanding!=1)||(ac->ICMPTargetValid))
		{
			assert(ac->ICMPTimeoutID==-1);		// should never have a timer going without a probe outstanding
			sidecarlog(LOGAPP,"got unknown icmp time exceeded\n");
			return;
		}
		ac->nIcmpProbesOutstanding=0;
		ac->ICMPTarget=ip.saddr;
		ac->ICMPTargetValid=1;				// tells icmp handlers who to send to
		if(ac->ICMPTimeoutID !=-1)
			sc_cancel_timer(con,ac->ICMPTimeoutID);
		ac->ICMPTimeoutID=-1;
		// 64 bytes from www.cs.umd.edu (128.8.128.160): icmp_seq=0 ttl=241 time=15.0 ms
		//fprintf(stdout,"%d bytes from %s (%s): icmp_seq=%d(%d) ttl=%d ",
		//		ntohs(ip.tot_len),TargetHost,TargetHostIp,ProbeCount,ntohs(ip.id),ip.ttl);
		schedule_next_icmp_probe(con);
		return;
	}
	if(icmp.type!=ICMP_ECHOREPLY)
	{
		sidecarlog(LOGAPP,"got unsolicited icmp packet: type=%d code=%d\n",icmp.type,icmp.code);
		return;
	}

	id = ntohs(icmp.un.echo.sequence);
	ap = (aprobe *)probe_lookup(con,id);
	if(ap)
	{
		if(ac->nIcmpProbesOutstanding==0)
		{
			sidecarlog(LOGAPP,"got duplicate icmp echo_reply packet: id=%d seq=%d\n",
					ntohs(icmp.un.echo.id),ntohs(icmp.un.echo.sequence));
			return;
		}
		sidecarlog(LOGAPP,"icmp probe returned id=%d(%d)\n",id,ntohs(ip.id));
		ac->nIcmpProbesOutstanding--;
		packet_get_ip_options(p,ap->options,&len);
		ap->status=PROBE_RECV;
		ap->recv=phdr->ts;
		if(ac->nIcmpProbesOutstanding<=0)	// if all probes have returned
		{
			diffPacketProbes(ac);
			schedule_next_icmp_probe(con);
			if(ac->ICMPTimeoutID !=-1)
				sc_cancel_timer(con,ac->ICMPTimeoutID);
			ac->ICMPTimeoutID=-1;
		}
		return;
	}
	sidecarlog(LOGAPP,"got unsolicited icmp echo reply packet: id=%d(%d)\n",id,ntohs(ip.id));
}

/*******************************************************************************************
 * artratcon * artratcon_new();
 * 	alloc a new artratcon structure
 */
artratcon * artratcon_new()
{
	artratcon *ac;
	int i;
	ac = malloc(sizeof(artratcon));
	memset(ac,0,sizeof(artratcon));
	ac->usBaseRtt=MAXINT;
	ac->usVJRtt=0;
	ac->usLastRtt=0;
	ac->usVJMdev=3*1000*1000;
	ac->ProbeOutstanding=0;
	ac->ProbeID=0;
	ac->ProbeCount=0;
	ac->TimeoutID=-1;
	ac->TotalProbes=0;
	ac->DropCount=0;

	ac->nIcmpProbesOutstanding=0;
	ac->nIcmpProbes=NProbes;
	ac->icmpprobes = malloc(NProbes*sizeof(aprobe*));
	assert(ac->icmpprobes);
	for(i=0;i<NProbes;i++)
	{
		ac->icmpprobes[i]=malloc(sizeof(aprobe));
		assert(ac->icmpprobes[i]);
		ac->icmpprobes[i]->seq=0;
		ac->icmpprobes[i]->status=PROBE_UNSENT;
		memset(&ac->icmpprobes[i]->sent,0,sizeof(struct timeval));
		memset(&ac->icmpprobes[i]->recv,0,sizeof(struct timeval));
		memset(ac->icmpprobes[i]->options,0,IP_MAX_OPTLEN);
	}

	ac->ICMPProbeCount=0;
	ac->ICMPTimeoutID=-1;
	ac->ICMPTotalProbes=0;
	ac->ICMPDropCount=0;
	ac->xminNeedInit=1;
	for(i=0;i<(IP_MAX_OPTLEN/4);i++)
	{
		ac->clockprecision[i]=ac->xmin[i]=MAXINT;
		ac->lastclock[i]=0;
	}
	return ac;
}

/*****************************************************************************************
 * int artratcon_free(artratcon *);
 * 	free resources associated with artratcon struct
 */

int artratcon_free(artratcon * ac)
{
	int i;
	assert(ac);
	for(i=0;i<ac->nIcmpProbes;i++)
		free(ac->icmpprobes[i]);
	free(ac->icmpprobes);
	free(ac);
	return 0;
}

/********************************************************************************************
 * void artrat_end_oneshot(struct connection *, void *);
 * 	time is up on the one shot connection;
 * 	close sock and return
 */

void artrat_end_oneshot(struct connection *con , void *ignore)
{
	sidecarlog(LOGAPP,"Shutting down OneShot socket\n");
	shutdown(OneShotSock,2);
	close(OneShotSock);
}

