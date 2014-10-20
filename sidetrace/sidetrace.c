/**********************************************************************************
 * SIDETRACE:	has functionality of netcat (`nc`), but uses sidecar to
 *		inject TTL limited probes (i.e., traceroute) into connection to
 *		discover topology; only tracking one connection
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
int UseRR=1;			// add RecordRoute IP option to packets by default
int NewRROnly=1;		// from TTL to TTL+1, only print the new RR entries
int ProbesPerHop = 3;		// by default, do like traceroute
int MaxHops = 30;		// only probe out to TTL=30
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
//int LogLevel=LOGCRIT;		// only log crit by default
int LogLevel=0;			// quiet, by default
int SendWget=0;			// read from stdin by default
int NextTTL=1;			// the next probe should send to this TTL
int Iteration=0;		// for Iteration=0 to ProbesPerHop, send probe
int DNSLookUpIPs=1;		// Lookup DNS names for ip addresses
int WaitTime=3;			// Default probe timeout
int ReachedEndHost=0;
/* 
int DropCount=0;
long RttMin=MAXINT;
long RttMax=0;
long RttAccum=0;
long RttVJAvg=0;
long RttMdev=3000000;
*/
struct timeval ProbeTimestamp = {0,0};
struct timeval StartTime;
#define BUFLEN 	4096

// protos
void parse_args(int argc, char * argv[]);
void usage(char *s1, char *s2);


void handle_sigio(int);

void sidetrace_initCB(void *);
void sidetrace_connectionCB(struct connection *);
void sidetrace_closeCB(struct connection *);
void sidetrace_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sidetrace_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sidetrace_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sidetrace_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
void sidetrace_sendprobe(struct connection *);
void sidetrace_timeout(struct connection *,void*);

const char * hostname2addressstr(char * host,char * dst,int len);
int sendwget(int sock);
void newrtt(struct timeval);
char * prettyTime(struct timeval,char *buf,int len);
void print_probe(int ttl, struct packet * probe, struct timeval time_received);
void schedule_first_probe(struct connection *);



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
	snprintf(buf,BUFLEN,"( src host %s and src port %d ) or ( dst host %s and dst port %d ) or icmp",
			TargetHost,TargetPort,TargetHost,TargetPort);
	if(hostname2addressstr(TargetHost,TargetHostIp,BUFLEN)==NULL)
	{
		fprintf(stderr,"ERR: Could not resolve Host '%s'\n",TargetHost);
		exit(2);
	}
	// traceroute to myleft.net (66.92.161.61), 30 hops max, 40 byte packets
	printf("sidetrace to %s (%s), %d hops max\n",TargetHost,TargetHostIp,MaxHops);
	fflush(stdout);
	// set log level
	sc_setlogflags(LogLevel);
	// tell sidecar to watch that stream
	sc_init(buf,Dev,0);
	// register callbacks with sidecar
	sc_register_connect(sidetrace_connectionCB);	// when we get a new connection
	sc_register_init(sidetrace_initCB,NULL);		// what to do first
	sc_do_loop();					// hand control to sidecar

	return 0;
}

/*******************************************************************
 * int sidetrace_init(void * ignore)
 * 	once sidecar is started, make a connection to the host:port pair
 * 	and set O_ASYNC and O_NONBLOCK on stdin so that when it becomes avail, 
 * 	we read from it
 */

void sidetrace_initCB(void * ignore)
{
	int flags,err,fd;
	gettimeofday(&StartTime,NULL);

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
 * void sidetrace_connectionCB(struct connection *);
 * 	gets called when connection is completed
 * 	- start the sendprobe timer
 */

void sidetrace_connectionCB(struct connection *con)
{
	sidecarlog(LOGAPP,"got new connectionCB\n");
	sc_register_close(sidetrace_closeCB,con);			// when to stop
	sc_register_in_handler(sidetrace_in_handler,con);		// tells us when to recv()
	sc_register_out_handler(sidetrace_out_handler,con);	// needed to timestamping outgoing packets
	sc_register_icmp_in_handler(sidetrace_icmp_in_handler,con);
	sc_register_icmp_out_handler(sidetrace_icmp_out_handler,con);
	// start ProbeID as half way through the sequence space
	ProbeID=(connection_get_ip_id(con)+0x7ffff)&0xffff;
	sc_register_idle(sidetrace_sendprobe,con,10000);	// wait for the conneciton to be idle 10MS
								// before sending first probe
}



/*************************************************************************
 * void sidetrace_closeCB(struct connection *);
 * 	connection is closed; shutdown sidecar
 */

void sidetrace_closeCB(struct connection *con)
{
	exit(0);	// when the connection is closed, just exit()
}

/**************************************************************************
 * void sidetrace_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *	Got an incoming tcp packet; if it's a redundant ack output time delta to stdout, else
 *	output data to stderr (unless webrequest is set)
 */

void sidetrace_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
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
		print_probe(NextTTL,p,phdr->ts);
		ReachedEndHost=1;
		sidetrace_sendprobe(con);
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
 *  void sidetrace_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *  	if this packet matches our current ProbeID, record the time
 */

void sidetrace_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	packet_get_ip_header(p,&ip);
	if(!ProbeOutstanding)
		return;
	if(ip.id != htons(ProbeID-1))
		return;
	// this is out outgoing probe packet; record time
	ProbeTimestamp = phdr->ts;
}

/*****************************************************************************************
 * void sidetrace_sendprobe(struct connection *,void*);
 * 	create and send probe packet; schedule timeout
 */

void sidetrace_sendprobe(struct connection * con)
{
	struct packet * probe;
	struct iphdr ip;
	struct icmp_header icmp;
	char buf[BUFLEN];
	char ipoptions[IP_MAX_OPTLEN];
	int optlen=IP_MAX_OPTLEN;

	if(Iteration<ProbesPerHop)
		Iteration++;
	else
	{
		if((ReachedEndHost)|| (NextTTL>=MaxHops))
		{
			printf("\n");
			exit(0);	// did everything
		}
		NextTTL++;
		Iteration=1;
	}	

	if(Iteration==1)
	{
		printf("%s%2d ",NextTTL==1?"":"\n",NextTTL);
		fflush(stdout);
	}
	probe = connection_make_packet(con);
	memset(buf,0,BUFLEN);
	packet_get_ip_header(probe,&ip);
	ip.id=htons(ProbeID++);
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
	ip.ttl=NextTTL;
	if(UseRR)
	{
		memset(ipoptions,0,IP_MAX_OPTLEN);
		ipoptions[0]=IPOPT_NOP;
		ipoptions[1]=IPOPT_RR;
		ipoptions[2]=IP_MAX_OPTLEN-1;
		ipoptions[3]=4;
		optlen=IP_MAX_OPTLEN;
		packet_set_ip_options(probe,ipoptions,optlen);
	}
	packet_set_ip_header(probe,&ip);
	sidecarlog(LOGAPP,"Sending new probe: %d \n",ProbeCount);
	ProbeOutstanding=1;
	ProbeCount++;
	packet_send(probe);
	sidecarlog(LOGAPP," scheduling timeout for tcp_seq=%d for %ld us\n",
			ProbeCount,WaitTime*1000000);
	ProbeTimestamp.tv_sec=ProbeTimestamp.tv_usec=0;
	TimeoutID=sc_register_timer(sidetrace_timeout,con,WaitTime*1000000,NULL);		// schedule timeout
}

/**************************************************************************************8
 * void sidetrace_timer(struct connection *,void*)
 * 	register the timeout, print and reschule next probe
 */

void sidetrace_timeout(struct connection *con,void*ignore)
{
	// fprintf(stderr,"ID: %d %u TIMEOUT\n",ProbeCount,ProbeID);
	printf(" * ");
	fflush(stdout);
	ProbeOutstanding=0;
	TimeoutID=-1;
	sidetrace_sendprobe(con);
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
	 while((c=getopt(argc,argv,"Id:i:wnR"))!=EOF)
	 {
		switch(c)
		{
			case 'I':
				UseICMP=1;
				break;
			case 'd':
				LogLevel=atoi(optarg);
				break;
			case 'i':
				Dev=strdup(optarg);
				break;
			case 'w':
				SendWget=1;
				break;
			case 'n':
				DNSLookUpIPs=0;
				break;
			case 'R':
				UseRR=0;
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
			"sidetrace [options] host port\n\n"
			"\t-I	-- use ICMP ECHO instead of tcp\n"
			"\t-d debuglevel	[%d]\n"
			"\t-i dev 	[auto]\n"
			"\t-w	 -- send http get [off]\n"
			"\t-n	 -- don't lookup DNS names [on]\n"
			"\t-R	 -- don't set Record Route IP Option [on]\n"
			"\t\n",
			LogLevel);
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
 * void sidetrace_icmp_in_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 * 	if this is an echo reply, then lookup time and print
 */

void sidetrace_icmp_in_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;

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
	print_probe(NextTTL,p,phdr->ts);
	sidetrace_sendprobe(con);
}
/***********************************************************************************************
 * void sidetrace_icmp_out_handler(struct connection *, struct packet *, const struct pcap_pkthdr *);
 *	record the time of the outgoing packet so we can calc the RTT when it returns
 */

void sidetrace_icmp_out_handler(struct connection *con, struct packet *p, const struct pcap_pkthdr *phdr)
{
	struct iphdr ip;
	packet_get_ip_header(p,&ip);
	if(!ProbeOutstanding)
	{
		fprintf(stderr,"Weird: got outgoing icmp packet with no probes outstanding\n");
		return;
	}
	if(ip.id != htons(ProbeID-1))
		return;
	// this is out outgoing probe packet; record time
	ProbeTimestamp = phdr->ts;
}

/********************************************************************************************
 * void print_rr_entries(struct packet *p,int ttl,FILE * out)
 * 	print the relevant RR entries from the packet in the bounce of this packet
 */

void print_rr_entries(struct packet *p,int ttl,FILE * out)
{
	static int saved_rrEntries[9];
	static int saved_nRREntries=0;
	int rrEntries[9];
	int nRREntries=0;
	char ipoptions[IP_MAX_OPTLEN];
	int ipoptionslen=IP_MAX_OPTLEN;
	struct packet * bounce;
	char data[BUFLEN];
	int datalen=BUFLEN;
	int i;
	struct sockaddr_in sa;
	char canon[BUFLEN+1],ipstr[BUFLEN+1];
	int err;

	packet_get_data(p,data,&datalen);
	if(datalen<=0)
		return;
	bounce = packet_make_from_buf((struct iphdr*) data,datalen);
	packet_get_ip_options(bounce,ipoptions,&ipoptionslen);
	memcpy(rrEntries,&ipoptions[4],sizeof(int)*9);	// copy options into place
	packet_free(bounce);
	nRREntries=(ipoptions[3]/4)-1;

	sa.sin_family=AF_INET;
	for(i=0;i<nRREntries;i++)
	{
		if((NewRROnly)&&(rrEntries[i]==saved_rrEntries[i]))
			continue;	// skip ones we have already printed
		inet_ntop(AF_INET,&rrEntries[i],ipstr,BUFLEN);
		sa.sin_addr.s_addr = rrEntries[i];
		err=getnameinfo((struct sockaddr *)&sa,sizeof(sa),
				canon,BUFLEN,
				NULL,0,
				0);
		if(err || (!DNSLookUpIPs)) 
			fprintf(out," RR%d=%s",i,ipstr);
		else
			fprintf(out," RR%d=%s(%s)",i,canon,ipstr);
	}
	memcpy(saved_rrEntries,rrEntries,sizeof(int)*9);	// copy old RRs into place
	saved_nRREntries=nRREntries;

	fflush(out);
}

/*****************************************************************************************8
 * void print_probe(int ttl, struct packet * p, struct timeval time_received)
 * 	got a probe back; figure out if it is a duplicate ACK or ICMP response, 
 * 		extract useful info and print to stdout
 */

void print_probe(int ttl, struct packet * p, struct timeval time_received)
{
	static int lastTTL=0;
	static unsigned int lastIP=0;

	char buf[BUFLEN];	
	char canon[BUFLEN];	
	int err;
	int saddr;
	struct iphdr ip;
	struct timeval diff;
	struct sockaddr_in sock_in;
	int len = BUFLEN;
	char * prefix = "";



	packet_get_ip_header(p,&ip);
	saddr = ip.saddr;
	sock_in.sin_family = PF_INET;
	sock_in.sin_addr.s_addr = saddr;
	if((ttl!=lastTTL)||(lastIP!=saddr))	// if this is a new address
	{
		inet_ntop(AF_INET,&saddr,buf,BUFLEN);
		if((ttl==lastTTL)&&(lastIP!=saddr))
			prefix="!";
		if(DNSLookUpIPs)
		{
			err=getnameinfo((struct sockaddr *)&sock_in,sizeof(sock_in),canon,len,NULL,0,0);
			if(!err)
				printf(" %s%s(%s) ",prefix,canon,buf);
		}
		if(!DNSLookUpIPs || err)	// if dont' want or have DNS info, just print IP
			printf(" %s%s ",prefix,buf);
		// FIXME : add RR parsing here
		lastTTL=ttl;
		lastIP=saddr;
		if(UseRR)
			print_rr_entries(p,ttl,stdout);
	}
	if(ProbeTimestamp.tv_sec==0 && ProbeTimestamp.tv_usec==0)
		printf(" ?");		// no timing information
	else
	{
		timersub(&time_received,&ProbeTimestamp,&diff);
		printf(" %s ",prettyTime(diff, buf, BUFLEN));
	}
	fflush(stdout);
}
/************************************************************************************************
 * void schedule_first_probe(struct connection *);
 * 	just call sidetrace_sendprobe()
 * 	we do this to make sure that the first probe is sent after the connection
 * 	is idle
 */

void schedule_first_probe(struct connection *con)
{
	sidetrace_sendprobe(con);	
}
