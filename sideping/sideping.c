/**********************************************************************************
 * SIDEPING:	has functionality of netcat (`nc`), but uses sidecar to
 *		inject configurable number of probes into connection to
 *		measure end-to-end round trip time ; only tracking one connection
 *		at a time, which is a waste of sidecar, but oh well
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
#include "netutils.h"


// globals (yes, this is an example, so I'll be lazy and use global vars)
int Sock=-1;
int UseICMP=0;			// use tcp by default; just here for comparison
int TotalProbes = -1;		// by default, limit probes by time
double ProbesPerSecond=1;		// Max probes :: each of max 41 bytes, so 10*41 = 3.2kbps
char * TargetHost = NULL;
char TargetHostIp[BUFLEN];	// ascii representation of ip address
int TargetPort=-1;
int LocalPort=0;
char * Dev=NULL;		// use pcap default
int ProbeOutstanding=0;
int ProbeID=-1;
int ProbeCount=-1;
int TimeoutID=-1;
int ConnectTimeout=3000;	// 3 second default timeout on connect()
int LogLevel=LOGCRIT;		// only log crit by default
int SendWget=0;			// read from stdin by default
int DropCount=0;
long RttMin=MAXINT;
long RttMax=0;
long RttAccum=0;
long RttVJAvg=0;
long RttMdev=3000000;
int Passive=0;
struct timeval ProbeTimestamp = {0,0};
struct timeval StartTime;
#define BUFLEN 	4096

// protos
void parse_args(int argc, char * argv[]);
void usage(char *s1, char *s2);


void handle_sigio(int);
void handle_sigint(int);

void sideping_initCB(void *);
void sideping_connectionCB(struct connection *);
void sideping_closeCB(struct connection *);
void sideping_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sideping_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sideping_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sideping_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sideping_sendprobe(struct connection *,void*);
void sideping_timeout(struct connection *,void*);

const char * hostname2addressstr(char * host,char * dst,int len);
int sendwget(int sock);
void newrtt(struct timeval);
char * prettyTime(struct timeval,char *buf,int len);


/**************
 * main():
 * 	parse_args, setup sidecar, then hand control to sidecar
 */


int main(int argc, char * argv[])
{
	char buf[BUFLEN];

	parse_args(argc, argv);
	if(TargetHost==NULL)
		usage("Need to specify host and port",NULL);
	if(TargetPort==-1)
		usage("Need to specify port",NULL);
	if(!Passive)
	{
		snprintf(buf,BUFLEN,"( src host %s and src port %d ) or ( dst host %s and dst port %d )",
				TargetHost,TargetPort,TargetHost,TargetPort);
		if(hostname2addressstr(TargetHost,TargetHostIp,BUFLEN)==NULL)
		{
			fprintf(stderr,"ERR: Could not resolve Host '%s'\n",TargetHost);
			exit(2);
		}
	}
	else
	{
		// in Passive mode, we only listen on the port
		snprintf(buf,BUFLEN,"port %d", TargetPort); 
		TargetHost="PASSIVE";
		strncpy(TargetHostIp,"PASSIVE_IP",BUFLEN);
	}
	signal(SIGINT,handle_sigint);	// catch control-c
	// set log level
	sc_setlogflags(LogLevel);
	// tell sidecar to watch that stream
	sc_init(buf,Dev,0);
	// register callbacks with sidecar
	sc_register_connect(sideping_connectionCB);	// when we get a new connection
	sc_register_init(sideping_initCB,NULL);		// what to do first
	sc_do_loop();					// hand control to sidecar

	return 0;
}

/*******************************************************************
 * int sideping_init(void * ignore)
 * 	once sidecar is started, make a connection to the host:port pair
 * 	and set O_ASYNC and O_NONBLOCK on stdin so that when it becomes avail, 
 * 	we read from it
 */

void sideping_initCB(void * ignore)
{
	int flags,err,fd;
	gettimeofday(&StartTime,NULL);

	if(Passive)		// wait for incoming connection
		return;
	// make connection
	Sock = make_tcp_connection(TargetHost,TargetPort,ConnectTimeout);
	if(Sock == -1)
	{
		perror("make_tcp_connection::");
		exit(1);
	}
	if(UseICMP)
		return;		// nothing left todo
	if(SendWget)
	{
		sendwget(Sock);
		return;
	}
	
	// else setup ASYNC handling to read from stdin
	signal(SIGIO,handle_sigio);
	// flag stdin as ASYNC 
	fd = fileno(stdin);
	flags = fcntl(fd,F_GETFL);
	if(flags==-1)
	{
		perror("fnctl(stdio,f_getfl)::");
		exit(1);
	}
	flags|=O_ASYNC|O_NONBLOCK;
	err = fcntl(fd,F_SETFL,flags);
	if(err==-1)
	{
		perror("fnctl(stdio,f_setfl)::");
		exit(1);
	}
}

/**********************************************************************
 * void handle_sigio(int);
 * 	we got SIGIO on stdin, so read from stdin, and write the contents
 * 	to the socket
 */

void handle_sigio(int sigtype)
{
	char buf[BUFLEN];
	int count,err;
	int fd = fileno(stdin);
	do 
	{
		count=read(fd,buf,BUFLEN);
		if(count>0)
			err=send(Sock,buf,BUFLEN,0);	// assume we can write it all in one send(); lazy

	} while((count>0)&&(err>0));

	if((count == -1)&&(errno != EAGAIN)&&(errno != EWOULDBLOCK))
	{
		perror("read() from stdin:: ");
		exit(1);
	}
	if(err == -1 )
	{
		perror("send() to socket:: ");
		exit(1);
	}
}

/***********************************************************************
 * void schedule_next_probe()
 * 	schedules the next probe, unless we have sent too many
 */

void schedule_next_probe(struct connection * con)
{
	long uswait = 1000000/ProbesPerSecond;
	ProbeID++;
	if(ProbeID>0xffff)					// must fit in 16 bits
		ProbeID=0;
	ProbeCount++;
	if((TotalProbes!=-1) && (ProbeCount>=TotalProbes))
	{
		handle_sigint(0);		// print our exit stats
		exit(0);
	}
	ProbeTimestamp.tv_sec=ProbeTimestamp.tv_usec = 0;	// mark this as uninitialized
	sc_register_timer(sideping_sendprobe,con,uswait,NULL);	// start the probe timer
}

/***********************************************************************
 * void sideping_connectionCB(struct connection *);
 * 	gets called when connection is completed
 * 	- start the sendprobe timer
 */

void sideping_connectionCB(struct connection *con)
{
	sidecarlog(LOGAPP,"got new connectionCB\n");
	sc_register_close(sideping_closeCB,con);			// when to stop
	sc_register_in_handler(sideping_in_handler,con);		// tells us when to recv()
	sc_register_out_handler(sideping_out_handler,con);	// needed to timestamping outgoing packets
	if(UseICMP)
	{
		sc_register_icmp_in_handler(sideping_icmp_in_handler,con);
		sc_register_icmp_out_handler(sideping_icmp_out_handler,con);
	}
	// start ProbeID as half way through the sequence space
	ProbeID=(connection_get_ip_id(con)+0x7ffff)&0xffff;
	schedule_next_probe(con);
}



/*************************************************************************
 * void sideping_closeCB(struct connection *);
 * 	connection is closed; shutdown sidecar
 */

void sideping_closeCB(struct connection *con)
{
	exit(0);	// when the connection is closed, just exit()
}

/**************************************************************************
 * void sideping_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *	Got an incoming packet; if it's a redundant ack output time delta to stdout, else
 *	output data to stderr (unless webrequest is set)
 */

void sideping_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct timeval diff;
	char buf[BUFLEN];
	int len;
	struct iphdr ip;
	if(packet_is_redundant_ack(p,con))
	{
		sidecarlog(LOGAPP,"got redundant ack\n");
		// got Probe response
		packet_get_ip_header(p,&ip);
		if(ProbeOutstanding!=1)
		{
			fprintf(stderr,"Got response to unknown probe: id=%u(%u)\n",
					ntohs(ip.id),ip.id);
			assert(TimeoutID==-1);		// should never have a timer going without a probe outstanding
			return;
		}
		ProbeOutstanding=0;
		if(TimeoutID !=-1)
			sc_cancel_timer(con,TimeoutID);
		TimeoutID=-1;
		// 64 bytes from www.cs.umd.edu (128.8.128.160): icmp_seq=0 ttl=241 time=15.0 ms
		if(!Passive)
		{
			fprintf(stdout,"%d bytes from %s (%s): tcp_seq=%d(%d) ttl=%d ",
					ntohs(ip.tot_len),TargetHost,TargetHostIp,ProbeCount,ntohs(ip.id),ip.ttl);
		}
		else
		{
			len=BUFLEN;
			connection_get_name(con,buf,&len);
			fprintf(stdout,"%d bytes from %s : tcp_seq=%d(%d) ttl=%d ",
					ntohs(ip.tot_len),buf,ProbeCount,ntohs(ip.id),ip.ttl);
		}
		if(ProbeTimestamp.tv_sec==0 && ProbeTimestamp.tv_usec == 0)
			fprintf(stdout,"UNMATCHED");
		else
		{
			timersub(&phdr->ts,&ProbeTimestamp,&diff);	// calc delta
			fprintf(stdout,"time=%s",prettyTime(diff,buf,BUFLEN));
			newrtt(diff);
		}
		fprintf(stdout," now=%ld.%.6ld s\n",phdr->ts.tv_sec,phdr->ts.tv_usec);
		schedule_next_probe(con);
	}
	else
	{
		// else this is non-probe traffic; write to stdout
		len = BUFLEN;
		packet_get_data(p,buf,&len);
		if((len>0)&&(SendWget==0))	// don't write if there is no data or a web get
			write(fileno(stderr),buf,len);
	}
}

/***************************************************************************
 *  void sideping_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *  	if this packet matches our current ProbeID, record the time
 */

void sideping_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	packet_get_ip_header(p,&ip);
	if(!ProbeOutstanding)
		return;
	if(ip.id != htons(ProbeID))
		return;
	// this is out outgoing probe packet; record time
	ProbeTimestamp = phdr->ts;
}

/*****************************************************************************************
 * void sideping_sendprobe(struct connection *,void*);
 * 	create and send probe packet; schedule timeout
 */

void sideping_sendprobe(struct connection * con,void* ignore)
{
	struct packet * probe;
	long rtt,mdev,count,rto;
	struct iphdr ip;
	struct icmp_header icmp;
	char buf[BUFLEN];

	probe = connection_make_packet(con);
	memset(buf,0,BUFLEN);
	packet_get_ip_header(probe,&ip);
	ip.id=htons(ProbeID);
	packet_set_ip_header(probe,&ip);
	if(UseICMP==0)
	{
		// use TCP; common case
		packet_fill_old_data(con,probe,1);		// this fills with the min data to solicit an ACK
	}
	else
	{
		// use ICMP; for comparison to TCP
		icmp.type=ICMP_ECHO;
		icmp.code=0;
		icmp.checksum=0;		// will get set at send
		icmp.un.echo.id=htons(getpid());// identify this ping as from this pid
		icmp.un.echo.sequence=htons(ProbeCount); 
		packet_set_icmp_header(probe,&icmp);
		packet_tag_icmp_ping_with_connection(probe,con);	// this helps sidecar demux on connections
									// NEEDS to be called AFTER ip.id is set
		ip.protocol=IPPROTO_ICMP;
	}
	packet_set_ip_header(probe,&ip);
	sidecarlog(LOGAPP,"Sending new probe: %d \n",ProbeCount);
	ProbeOutstanding=1;
	packet_send(probe);
	// calc RTO for packet
	connection_get_rtt_estimate(con,&rtt,&mdev,&count);
	if((ProbeCount-DropCount)<1)            // if no estimates, used rto=rtt+2*mdev (TCP/IP Illustrated Vol1, p 305
		rto=2*RttMdev;
	else
		rto= RttVJAvg+4*RttMdev;
	sidecarlog(LOGAPP," scheduling timeout for tcp_seq=%d for %ld us\n",
			ProbeCount,rto);
	TimeoutID=sc_register_timer(sideping_timeout,con,rto,NULL);		// schedule timeout
}

/**************************************************************************************8
 * void sideping_timer(struct connection *,void*)
 * 	register the timeout, print and reschule next probe
 */

void sideping_timeout(struct connection *con,void*ignore)
{
	fprintf(stderr,"ID: %d %u TIMEOUT\n",ProbeCount,ProbeID);
	ProbeOutstanding=0;
	DropCount++;
	TimeoutID=-1;
	schedule_next_probe(con);
}


/**************************************************************************************
 *  void parse_args(int argc, char * argv[]);
 *  	parse arguments :: add some actual arg parsing here
 */

void parse_args(int argc, char * argv[])
{
	int c;
	/*
	if(argc!=3)
		return;
	TargetHost=strdup(argv[1]);
	TargetPort=atoi(argv[2]);
	*/
	 while((c=getopt(argc,argv,"c:Id:i:pr:w"))!=EOF)
	 {
		switch(c)
		{
			case 'c':
				TotalProbes=atoi(optarg);
				break;
			case 'I':
				UseICMP=1;
				break;
			case 'd':
				LogLevel=atoi(optarg);
				break;
			case 'i':
				Dev=strdup(optarg);
				break;
			case 'p':
				Passive=1;
				break;
			case 'r':
				ProbesPerSecond=atof(optarg);
				break;
			case 'w':
				SendWget=1;
				break;
			default:
				usage("unknown option",argv[optind]);
				break;
		}
	 }
	 if(optind<argc)
		 TargetHost=strdup(argv[optind++]);
	 if(optind<argc)
		 TargetPort=atoi(argv[optind++]);
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
			"sideping [options] host port\n\n"
			"\t-c count -- only send count probes\n"
			"\t-I	-- use ICMP ECHO instead of tcp\n"
			"\t-d debuglevel	[%d]\n"
			"\t-i dev 	[auto]\n"
			"\t-p -- passive mode [off] just listen on port, don't connect\n"
			"\t-r probes/sec	[%f] e.g, 0.25-->1probe/4sec\n"
			"\t-w	 -- send http get [off]\n"
			"\t\n",
			LogLevel,
			ProbesPerSecond);
	exit(2);
}
 
/*************************************************************************************
 * void hostname2addressstr(char * host,char * dst,int len);
 * 	turns "www.foo.org" into "128.8.128.118"
 */

const char * hostname2addressstr(char * host,char * dst,int len)
{
	struct hostent *h;

	h=gethostbyname(host);
	if(h==NULL)
	{
		return NULL;
	}
	return inet_ntop(AF_INET,h->h_addr,dst,len);
}

/*******************************************************************************
 * int sendwget(int sock);
 * 	send an http GET request for /index.html
 * 		fill in user@hostname for User-agent
 */

int sendwget(int sock)
{
	char buf[BUFLEN];
	char *user,*host;
	user = getenv("USER");
	if(!user)
		user="postmaster";	// just so it goes to someone!
	host = getenv("HOSTNAME");
	if(!host)
		host="localhost";	// should have better default, but this shouldn' fail
	fprintf(stderr,"GET http://%s:%d/index.html from %s@%s\n",
			TargetHost,TargetPort,user,host);
	snprintf(buf,BUFLEN,
			"GET /index.html HTTP/1.1\r\n"
			"Host: %s\r\n"
			"User-Agent: Mozilla/5.0 (Compat: Sidecar/TCPrtt %s@%s for concerns)\r\n"
			"Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5\r\n"
			"Accept-Language: en-us,en;q=0.5\r\n"
			"Accept-Encoding: gzip,deflate\r\n"
			"Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7\r\n"
			"Keep-Alive: 300\r\n"
			"Connection: keep-alive\r\n"
			"\r\n", TargetHost,user,host);
	return send(sock,buf,strlen(buf),0);
}
/*********************************************************************************
 * void handle_sigint(int ignore);
 * 	print stats when people hit ctr-c, then exit
 * 	--- xor.cs.umd.edu ping statistics ---
 * 	2 packets transmitted, 2 received, 0% packet loss, time 1000ms
 * 	rtt min/avg/max/mdev = 16.479/16.801/17.124/0.347 ms, pipe 2
 *
 */

void handle_sigint(int ignore)
{
	struct timeval now,diff;
	double rttAvg;
	if(ProbeOutstanding)
		ProbeCount--;		// don't count outstanding probe
	gettimeofday(&now,NULL);
	timersub(&now,&StartTime,&diff);
	if(ProbeCount-DropCount>0)
		rttAvg = (double)RttAccum/(ProbeCount-DropCount);
	else
		rttAvg = -1.0;
	fprintf(stderr,"\n--- %s ping statistics ---\n"
			"%d packets transmited, %d received, %lf%% packet loss, time %ld.%.6ld s\n"
			"rtt min/VJavg/avg/max/VJmdev = %.3f/%.3f/%.3f/%.3f/%.3f ms, pipe %d\n",
			TargetHost,
			ProbeCount, ProbeCount-DropCount, 100.0*(double)DropCount/ProbeCount, 
			diff.tv_sec,diff.tv_usec,
			0.001*RttMin,0.001*RttVJAvg,0.001*rttAvg,0.001*RttMax,0.001*RttMdev, ignore);
	exit(0);
}

/**********************************************************************************
 * void newrtt(struct timeval rtt);
 * 	we have a new data point for rtts, update statistics
 */

void newrtt(struct timeval rtt_tv)
{
	long rtt_est;
	long err;

	rtt_est = 1000000*rtt_tv.tv_sec+rtt_tv.tv_usec;
	if(rtt_est<RttMin)
		RttMin=rtt_est;
	if(rtt_est>RttMax)
		RttMax=rtt_est;
	
	// VJ's three magic lines
	err = rtt_est - RttVJAvg;
	RttVJAvg +=(err>>3);
	RttMdev+= (labs(err)-RttMdev)>>2;  // labs() == abs() for longs, who knew?
	RttAccum+=rtt_est;
}

/***************************************************************************************
 * char * prettyTime(struct timeval t,char *buf,int len);
 * 	prints time into a string with the appropriate unit
 */

char * prettyTime(struct timeval tv, char * buf, int len)
{
	long t = 1000000*tv.tv_sec+tv.tv_usec;
	if(t>1000000)
		snprintf(buf,len,"%.6f s",(double)t/1000000);
	else if(t>1000)
		snprintf(buf,len,"%.3f ms",(double)t/1000);
	else 
		snprintf(buf,len,"%f us",(double)t);
	return  buf;
}

/****************************************************************************************
 * void sideping_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 * 	if this is an echo reply, then lookup time and print
 */

void sideping_icmp_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	struct timeval diff;
	char buf[BUFLEN];
	int len;

	sidecarlog(LOGAPP,"got icmp echoreply\n");
	// got Probe response
	packet_get_ip_header(p,&ip);
	if(ProbeOutstanding!=1)
	{
		fprintf(stderr,"Got response to unknown probe: id=%u(%u)\n",
				ntohs(ip.id),ip.id);
		assert(TimeoutID==-1);		// should never have a timer going without a probe outstanding
		return;
	}
	ProbeOutstanding=0;
	if(TimeoutID !=-1)
		sc_cancel_timer(con,TimeoutID);
	TimeoutID=-1;
	// 64 bytes from www.cs.umd.edu (128.8.128.160): icmp_seq=0 ttl=241 time=15.0 ms
	if(!Passive)
	{
		fprintf(stdout,"%d bytes from %s (%s): icmp_seq=%d(%d) ttl=%d ",
				ntohs(ip.tot_len),TargetHost,TargetHostIp,ProbeCount,ntohs(ip.id),ip.ttl);
	}
	else
	{
		len=BUFLEN;
		connection_get_name(con,buf,&len);
		fprintf(stdout,"%d bytes from %s : icmp_seq=%d(%d) ttl=%d ",
				ntohs(ip.tot_len),buf,ProbeCount,ntohs(ip.id),ip.ttl);
	}
	if(ProbeTimestamp.tv_sec==0 && ProbeTimestamp.tv_usec == 0)
		fprintf(stdout,"UNMATCHED");
	else
	{
		timersub(&phdr->ts,&ProbeTimestamp,&diff);	// calc delta
		fprintf(stdout,"time=%s",prettyTime(diff,buf,BUFLEN));
		newrtt(diff);
	}
	fprintf(stdout," now=%ld.%.6ld s\n",phdr->ts.tv_sec,phdr->ts.tv_usec);
	schedule_next_probe(con);
}
/***********************************************************************************************
 * void sideping_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *	record the time of the outgoing packet so we can calc the RTT when it returns
 */

void sideping_icmp_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	packet_get_ip_header(p,&ip);
	if(!ProbeOutstanding)
	{
		fprintf(stderr,"Weird: got outgoing icmp packet with no probes outstanding\n");
		return;
	}
	if(ip.id != htons(ProbeID))
		return;
	// this is out outgoing probe packet; record time
	ProbeTimestamp = phdr->ts;
}

