#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>


#define SHOULD_DUMP_PACKET 0x00

#include "context.h"
#include "log.h"
#include "packet.h"
#include "sidecar.h"
#include "utils.h"

#include "pmdb_echoidcache.h"

static packet * packet_make_icmp_from_buf(packet *p,struct iphdr * ip, int caplen);
static int packet_fill_old_synack(struct connection * con, packet * p);
static int packet_fill_old_finack(struct connection * con, packet * p);
static int recalc_sizes(struct packet *p);
static int packet_refinc(struct packet *p);
static void packet_dump(unsigned char * buf, int len,FILE * out);
static int decode_mpls_extensions(u_char *buf, int ip_len, struct mpls_header *mpls);

/********************************************************************
 * packet * packet_make_from_buf(struct iphdr *, int caplen);
 * 	given a buffer that contains an ip header and data,
 * 	transform it into a packet structure
 * 	 - be careful not to over run a buffer when we have only captured
 * 	 the first 'caplen' bytes
 *
 */
packet * packet_make_from_buf(struct iphdr * ip, int caplen)
{
	packet *p;
	
	p = malloc_and_test(sizeof(packet)); /* leaks. */
	assert(p!=NULL);
	assert(caplen>=(sizeof(struct iphdr)+8));		// assert() we get at least an ICMP payload

	memset(p,0,sizeof(packet));	// zero everything
	memcpy(&p->ip,ip,sizeof(struct iphdr));
	p->magic=PACKET_MAGIC;
	p->refcount=1;
	// Invalid assert()!  Could be called with a caplen from an ICMP packet payload with *&!^ MPLS cruft
	// BAD assert(ntohs(ip->tot_len) <= caplen);
	p->type=ip->protocol;
	p->hasMpls = decode_mpls_extensions((u_char *)ip,caplen,&p->mpls);
	if(ip->ihl>5)
	{
		p->ip_opt_len = (ip->ihl*4)-sizeof(struct iphdr);
		p->ip_opts=malloc_and_test(p->ip_opt_len);
		assert(p->ip_opts);
		memcpy(p->ip_opts,&ip[1],p->ip_opt_len);
	}	// else, ip_opt_len and ip_opts are already zero by memset
	switch(p->type)
	{
		case IPPROTO_TCP:
			memcpy(&p->tcp,(unsigned char *)ip+ip->ihl*4,MIN(sizeof(struct tcphdr),caplen-ip->ihl*4));	
			p->datalen=MIN(caplen,ntohs(ip->tot_len))-(p->tcp.doff+ip->ihl)*4;
			if(p->datalen>0)
			{	// copy the data if it exists
				p->data = malloc_and_test(p->datalen);
				assert(p->data);
				memcpy(p->data,(unsigned char *)ip+(ip->ihl+p->tcp.doff)*4,p->datalen);
			} else
				p->data=NULL;
			if(p->tcp.doff>5)		// packet has tcp options
			{
				p->tcp_opt_len=4*p->tcp.doff-sizeof(struct tcphdr);
				p->tcp_opts=malloc_and_test(p->tcp_opt_len);
				memcpy(p->tcp_opts,(unsigned char *)ip+ip->ihl*4+sizeof(struct tcphdr),p->tcp_opt_len);
			} else {
				p->tcp_opt_len=0;
				p->tcp_opts=NULL;
			}

			break;
		case IPPROTO_ICMP:
          /* what happens to newly allocated p? */
			return packet_make_icmp_from_buf(p,ip,caplen);  // jump off elsewhere for clarity
			break;
		default:
			sidecarlog(LOGINFO,"packet_make_from_buf: dunno how to handle ip proto %d -- ignoring\n",
					p->type);

	};
	
	recalc_sizes(p);
	return p;
}
/*************************************************************************************
 * static packet * packet_make_icmp_from_buf(packet *p,struct iphdr * ip, int caplen)
 * 	we know this buf is an icmp packet, and the packet *p points to an already malloc'ed
 * 	packet structure with ip header and optionsfilled in
 * 	-- just fill in the rest of the packet
 */


static packet * packet_make_icmp_from_buf(packet *p,struct iphdr * ip, int caplen)
{
	memcpy(&p->icmp,(unsigned char *)ip+ip->ihl*4,sizeof(struct icmphdr));	// intentionally all of data
										// fields, even if they aren't valid
	switch(p->icmp.type)
	{
		case ICMP_TIME_EXCEEDED:
		case ICMP_DEST_UNREACH:
		case ICMP_ECHOREPLY:
		case ICMP_ECHO:
		case ICMP_PARAMETERPROB:
			// MIN(packet size,what we got) - icmp header - ip header = datalen
			p->datalen=MIN(caplen,ntohs(ip->tot_len))-ip->ihl*4-8;
			p->data = malloc_and_test(p->datalen);
			assert(p->data);
			memcpy(p->data,(unsigned char *)ip+ip->ihl*4+8,p->datalen);
			break;
			break;
		default:
			// there are a bunch of random ICMP types that deserve better treatment
			sidecarlog(LOGINFO,"packet_make_icmp_from_buf: NEED to implement parseing for "
					"ICMP type %d code %d!!!\n" , p->icmp.type, p->icmp.code);
            /* maybe free p? */
			return NULL;
	}
	return p;
}

/**************************************************************************
 * int packet_fill_old_data(struct connection *,struct packet *, int datalen);
 * 	given a connection and a packet, fill the packet with previously sent data
 * 	if the amount avail is less than requested, fill in amount avail
 * 	 - the return value is the amount of data filled in
 * 	from the connection.
 * 	- if the connection is closed, also set the FIN
 * 		Special case 1: if only 1 byte is asked for, and no data has been sent,
 * 			set packet up as the SYN|ACK from the 3-way handshake
 * 		Special case 2: if only 1 byte is acked for and the connection is closed,
 * 			send no data, and set FIN|ACK
 *
 * 	NOTE: if datalen>MTU, this does proc does nothing to split packets or prevent
 * 	fragmentation; caveat emptor
 */

int packet_fill_old_data(struct connection *con,struct packet * p, int datalen)
{
	assert(p->magic==PACKET_MAGIC);
	int len;
	if((datalen==1)&&(con->oldDataIndex==0)&&(con->oldDataFull==0))
		return packet_fill_old_synack(con,p);	// special case 1
	if(((con->state==CLOSED)||(con->state==TIMEWAIT))&&(datalen==1))
		return packet_fill_old_finack(con,p);	// special case 2
	// general case
	if(con->oldDataFull)
		len = MIN(datalen,con->oldDataMax);
	else
		len = MIN(datalen,con->oldDataIndex);
	if(len==0)
		return 0;	// no data to fill
	if(len<=con->oldDataIndex)
	{
		packet_set_data(p,&con->oldData[con->oldDataIndex-len],len);
	} 
	else 
	{
		p->data = malloc_and_test(sizeof(len));
		assert(p->data);
		p->datalen=len;
		// from middle to end
		memcpy(p->data,&con->oldData[con->oldDataIndex],con->oldDataMax-con->oldDataIndex);	
		// from front to middle
		memcpy(&p->data[con->oldDataMax-con->oldDataIndex],con->oldData,
				len - con->oldDataMax - con->oldDataIndex); 
	}
	p->tcp.seq=htonl(ntohl(p->tcp.seq)-len);// set the seq number back so the packet looks valid
	recalc_sizes(p);
	return len;
}

/********************************************************************************
 * int packet_fill_old_synack(struct connection * con, packet * p);
 * 	make this packet look like the syn|ack from the 3-way handshake
 * 	ASSUMES: that the seq no in the passed packet is ISN+1
 */

int packet_fill_old_synack(struct connection * con, packet * p)
{
	assert(p->magic==PACKET_MAGIC);
	p->tcp.syn=p->tcp.ack=1;
	p->tcp.seq=htonl(ntohl(p->tcp.seq)-1);	// looks weird, but is right
	return 1;
}


/********************************************************************************
 * int packet_fill_old_finack(struct connection * con, packet * p);
 * 	make this packet look like the fin|ack from connection tear down
 */

int packet_fill_old_finack(struct connection * con, packet * p)
{
	assert(p->magic==PACKET_MAGIC);
	p->tcp.fin=p->tcp.ack=1;
	p->tcp.seq=htonl(ntohl(p->tcp.seq)-1);	// b/c the FIN has already been sent locally, 
						// our connection tracker seq is ahead by one
	p->tcp.ack_seq=htonl(con->rSeq);
	return 1;
}

/***************************************************************************
 * struct packet * packet_create():
 * 	creates an empty packet with zero'd fields
 */

struct packet * packet_create()
{
	packet * p;
	p = malloc_and_test(sizeof(packet));
	assert(p);
	memset(p,0,sizeof(packet));
	p->magic=PACKET_MAGIC;
	p->refcount=1;
	p->type=IPPROTO_TCP;	// tcp packet by default
	p->hasMpls=0;		// MPLS is evil: place thumbs in ears and cover eyes
	recalc_sizes(p);
	return p;
}
 


/***************************************************************************
 * int packet_free(struct packet *);
 * 	free all of the mem assosociated with packet struct
 */

int packet_free(packet * p )
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	p->refcount--;
	if(p->refcount>0)
		return 0;
	if(p->data)
	{
		free(p->data);
		p->data=NULL;
	}
	if(p->ip_opts)
	{
		free(p->ip_opts);
		p->ip_opts=NULL;
	}
	if(p->tcp_opts)
	{
		free(p->tcp_opts);
		p->tcp_opts=NULL;
	}
    memset(p, 0, sizeof(packet));
    p->magic = 0xcafebeef;
	free(p);
	return 0;
}

/****************************************************************************
 * int packet_set_ip_header(struct packet *, struct iphdr *);
 * 	set the ip header
 */
int packet_set_ip_header(struct packet * p , struct iphdr * ip)
{
 	assert(p);
	assert(p->magic==PACKET_MAGIC);
	p->ip=*ip;
	recalc_sizes(p);
	return 0;
}

/****************************************************************************
 * int packet_get_ip_header(struct packet *, struct iphdr *);
 * 	get the ip header
 */
int packet_get_ip_header(const struct packet *p, struct iphdr * ip)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	*ip=p->ip;
	return 0;
}

/****************************************************************************
 * int packet_set_icmp_header(struct packet *, struct icmphdr *);
 * 	set the icmp header
 */
int packet_set_icmp_header(struct packet * p , struct icmp_header * icmp)
{
 	assert(p);
	assert(p->magic==PACKET_MAGIC);
	p->icmp=*icmp;
	p->type=IPPROTO_ICMP;
	recalc_sizes(p);
	return 0;
}

/****************************************************************************
 * int packet_get_icmp_header(struct packet *, struct icmphdr *);
 * 	get the icmp header
 */
int packet_get_icmp_header(struct packet *p, struct icmp_header * icmp)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	assert(p->type==IPPROTO_ICMP);
	*icmp=p->icmp;
	return 0;
}

/****************************************************************************
 * int packet_set_tcp_header(struct packet *, struct tcphdr *);
 * 	set the tcp header
 */
int packet_set_tcp_header(struct packet * p , struct tcphdr * tcp)
{
 	assert(p);
	assert(p->magic==PACKET_MAGIC);
	p->tcp=*tcp;
	p->type=IPPROTO_TCP;
	recalc_sizes(p);
	return 0;
}

/****************************************************************************
 * int packet_get_tcp_header(struct packet *, struct tcphdr *);
 * 	get the tcp header
 */
int packet_get_tcp_header(struct packet *p, struct tcphdr * tcp)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	assert(p->type==IPPROTO_TCP);
	*tcp=p->tcp;
	return 0;
}

/******************************************************************************
 * int packet_set_ip_options(struct packet *, char *options, int optlen);
 * 	ip_options accessor funct
 */
int packet_set_ip_options(struct packet *p, char *options, int optlen)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	if(p->ip_opts)
		free(p->ip_opts);
	p->ip_opt_len=optlen;
	p->ip_opts=malloc_and_test(optlen);
	assert(p->ip_opts);
	memcpy(p->ip_opts,options,optlen);
	recalc_sizes(p);
	return 0;
}
/*********************************************************************************
 * int packet_get_ip_options(struct packet *, char *options, int *optlen);
 * 	copy as much of ip options into options as possible
 * 	set optlen to amount copied
 * 	return total amount available
 */
int packet_get_ip_options(struct packet *p, char *options, int *optlen)
{
	int l;
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	l = MIN(*optlen,p->ip_opt_len);
	memcpy(options,p->ip_opts,l);
	*optlen=l;
	return p->ip_opt_len;
}

/******************************************************************************
 * int packet_set_tcp_options(struct packet *, char *options, int optlen);
 * 	tcp_options accessor funct
 */
int packet_set_tcp_options(struct packet *p, char *options, int optlen)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	if(p->tcp_opts)
		free(p->tcp_opts);
	if(optlen%4)
	{
		sidecarlog(LOGCRIT,"packet_set_tcp_options:: optlen not divisible by four: %d\n",
				optlen);
		return 1;
	}
	p->tcp_opt_len=optlen;
	p->tcp_opts=malloc_and_test(optlen);
	p->tcp.doff=5+(optlen/4);
	assert(p->tcp_opts);
	memcpy(p->tcp_opts,options,optlen);
	recalc_sizes(p);
	return 0;
}
/*********************************************************************************
 * int packet_get_tcp_options(struct packet *, char *options, int *optlen);
 * 	copy as much of tcp options into options as possible
 * 	set optlen to amount copied
 * 	return total amount available
 */
int packet_get_tcp_options(struct packet *p, char *options, int *optlen)
{
	int l;
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	l = MIN(*optlen,p->tcp_opt_len);
	memcpy(options,p->tcp_opts,l);
	*optlen=l;
	return p->tcp_opt_len;
}

/*********************************************************************************
 * int packet_set_data(struct packet*, char * data, int datalen);
 * 	application data accessor funct
 */
int packet_set_data(struct packet *p, char * data, int datalen)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	if(p->data)
		free(p->data);
	p->datalen=datalen;
	p->data=malloc_and_test(datalen);
	assert(p->data);
	memcpy(p->data,data,datalen);
	recalc_sizes(p);
	return 0;
}

/**********************************************************************************
 * int packet_get_data(struct packet*, char * data, int *datalen);
 * 	application data accessor funct
 */

int packet_get_data(const struct packet*p, char * data, int *datalen)
{
	int l;
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	l= MIN(*datalen,p->datalen);
	memcpy(data,p->data,l);
	*datalen=l;
	return p->datalen;
}

/********************************************************************************
 * int packet_get_mpls(struct packet *, struct mpls_header * mpls)
 * 	return mpls, if we have it
 * 	mpls is garbage if we don't have it
 */

int packet_get_mpls(const struct packet *p, struct mpls_header * mpls)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	memcpy(mpls,&p->mpls,sizeof(struct mpls_header));
	return p->hasMpls;
}


/**************************************************************************
 *  int packet_send_now(struct tapcontext *)
 *  	snag first packet out of outgoing queue
 *  	make a big buffer out out of packet structure
 *  	fill in all internal checksums
 *  	then push out raw sock	(assumes IP_HDRINCL has been set)
 *		return err code from sendto();
 */ 

int packet_send_now(struct tapcontext *ctx)
{
	struct packet *p;
	struct tcphdr * tcp;
	struct icmp_header *icmp;
	struct iphdr *ip;
	char *buf;
	int err,len;
	struct pseudohdr *phdr;
	struct sockaddr_in sa_in;

	assert(ctx);
	// grab first packet off of queue
	p = (packet *) Q_Dequeue(ctx->outPacketQ);

	assert(p);
	assert(p->magic==PACKET_MAGIC || p->magic==0xcafebeef); // was corrupted
	assert(p->magic==PACKET_MAGIC);  // was freed
	assert(p->ip.ihl == ((sizeof(iphdr)+p->ip_opt_len)/4));
	assert((p->ip_opt_len%4)==0);
	assert(p->ip.ttl!=0);		// causes planetlab to be unhappy
	assert(p->type==p->ip.protocol);

	switch(p->type)
	{
		case IPPROTO_TCP:
			len = sizeof(struct iphdr)+p->ip_opt_len+sizeof(struct tcphdr)+p->tcp_opt_len+p->datalen;
			assert(p->tcp.doff == ((sizeof(tcphdr)+p->tcp_opt_len)/4));
			assert((p->tcp_opt_len%4)==0);
			break;
		case IPPROTO_ICMP:
			len = sizeof(struct iphdr)+p->ip_opt_len+sizeof(struct icmp_header)+p->datalen;
			break;
		default:
			sidecarlog(LOGCRIT," packet type %d not implemented!\n",p->type);
			abort();
	}
	assert(p->ip.tot_len == htons(len));
	buf = (char *) malloc_and_test(len);
	assert(buf);
	memset(buf,0,len);
	ip = (struct iphdr *)buf;
	if(p->type==IPPROTO_TCP)
	{
		tcp = (struct tcphdr*)((char *)buf + sizeof(struct iphdr)+p->ip_opt_len);
		p->tcp.check=0;	// we are going to re-calc the checksum, so zero it first
		// fill in pseudo hdr
		phdr = (struct pseudohdr*)(((char *)tcp)-sizeof(struct pseudohdr));	// backup from tcp header
		assert((void *)phdr >= (void *)buf);
		assert((void *)phdr < (void *)tcp);

	    /* valgrind believes that phdr ends up less than buf, which causes a bad write and 
	       perhaps eventually a seg fault.  These assertions try to figure it out. */
	    /* ahh, but only on nspring's athlon... */
		assert(sizeof(struct pseudohdr) == 12);
		assert(sizeof(struct pseudohdr) < sizeof(struct iphdr));
		assert(p->ip_opt_len >= 0);

		phdr->s_addr = p->ip.saddr;
		phdr->d_addr = p->ip.daddr;
		phdr->zero=0;
		phdr->proto=p->type;
		phdr->length = htons(p->datalen+ sizeof(struct tcphdr)+p->tcp_opt_len);


		// fill in tcp hdr
		memcpy(tcp,&p->tcp,sizeof(struct tcphdr));
		// fill in tcp opts
		memcpy(&tcp[1],p->tcp_opts,p->tcp_opt_len);
		// copy application data
		memcpy(((char*)tcp+sizeof(struct tcphdr)+p->tcp_opt_len),p->data,p->datalen);
		// do tcp check sum
		tcp->check = in_cksum((unsigned short *)phdr, sizeof(struct pseudohdr)+sizeof(struct tcphdr)+p->tcp_opt_len+p->datalen);
		sa_in.sin_port = htons(p->tcp.dest);
	}
	else if(p->type == IPPROTO_ICMP)
	{
		icmp = (struct icmp_header*)((char *)buf + sizeof(struct iphdr)+p->ip_opt_len);
		p->icmp.checksum=0;	// we are going to re-calc the checksum, so zero it first
		memcpy(icmp,&p->icmp,sizeof(struct icmp_header));
		// copy packet payload into place
		memcpy(((char*)icmp+sizeof(struct icmp_header)),p->data,p->datalen);
		// note that the mechanics to force Sidecar to associate this packet or the response 
		// as with the sidecar connection that sent it are not here
		// and need to be handled by the application by calling packet_tag_icmp_ping_with_connection()
		icmp->checksum = in_cksum((unsigned short *)icmp, sizeof(struct icmp_header)+p->datalen);
		sa_in.sin_port = 0;		// I guess this is right
		
	}
	// fill in ip checksum
	p->ip.check = in_cksum((unsigned short *)ip, sizeof(struct iphdr)+p->ip_opt_len);
	// put iphdr in place
	memcpy(ip,&p->ip,sizeof(struct iphdr));
	// put ip options in place
	memcpy(&ip[1],p->ip_opts,p->ip_opt_len);
	sa_in.sin_family=AF_INET;
	// sa_in.sin_port was set above
	sa_in.sin_addr.s_addr = p->ip.daddr;
	// send
	err = sendto(SidecarCtx->rawSock,buf,len,0,(struct sockaddr *) &sa_in, sizeof(sa_in));
	if(err<0)
	{
		if((errno==EAGAIN)||(errno==EWOULDBLOCK)) 
		{	// this packet would block
			Q_Push(ctx->outPacketQ,p);	// push it back on, and try again later
			packet_refinc(p); /* another reference to count, now that it's in the queue again */
		} 
		else 
		{
			sidecarlog(LOGDEBUG,"packet_send::send: %s\n",strerror(errno));
			if(errno==EPERM)
			{
				if(SHOULD_DUMP_PACKET)
				{
					packet_dump((unsigned char *)buf, len,stderr);
				 	abort();
				}
				SidecarCtx->epermCount++;
			}
		}
	} 
	else
	{
		SidecarCtx->sentCount++;		// update stats
		SidecarCtx->sentByteCount+=len;
		SidecarCtx->sendBudget-=len;		// charge the rate limiting bucket
	}

    packet_free(p); /* if in Q again, not quite free */
    free(buf);
    return err;
}

/**************************************************
 * int packet_send(struct packet *)
 * 	just enqueue packet onto outgoing Q 
 */

int packet_send(struct packet * p)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	assert(SidecarCtx);
	packet_refinc(p);
	return (Q_Enqueue(SidecarCtx->outPacketQ,p)==0);
}


/**********************************************************************************
 * int packet_send_train(struct packet **, int nPackets);
 * 	someday this will be something slicker... we still track the actual
 * 	leave times via libpcap, so it's not so bad
 */

int packet_send_train(struct packet **p, int nPackets)
{
	int i;
	int err;
	for(i=0;i<nPackets;i++)	
	{
		err= packet_send(p[i]);
		if(err<0)	// short cut on error
			return err;
	}
	return i;
}



/******************************************************************************
 * int packet_is_dupack(struct packet *, struct connection *);
 * 	return 1 if the packet is a duplicate acknowledgment, 0 otherwise
 */
int packet_is_dupack(struct packet * p, struct connection * con)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	assert(con);
	
	if((p->type!=IPPROTO_TCP)|| !p->tcp.ack)		// can't be a dup ack if it's not a tcp ack
		return 0;
	if(ntohl(p->tcp.ack_seq)>con->ackrecved)	// is this ACK higher than our current highest ACK?
		return 0;
	else 
		return 1;
}

/*******************************************************************************
 * int packet_is_redundant_ack(struct packet *, struct connection *);
 * 	return 1 if packet is dupack AND if all outstanding data has already been
 * 	acknowledged -- i.e., this packet is most likely generated by sidecar measurement
 * 	data
 */

int packet_is_redundant_ack(struct packet *p, struct connection *con)
{
	assert(p->magic==PACKET_MAGIC);
	if(!packet_is_dupack(p,con))
		return 0;
	if(p->tcp.fin)		// FIN|ACK's are never redundant
		return 0;
	if(p->datalen>0)
		return 0;	// the packet has data in it, not redundant
	if(con->ackrecved>=con->lSeq)	// has all data been acknowledged?
		return 1;
	else 
		return 0;
}

/******************************************************************************
 * struct packet * packet_duplicate(struct packet *);
 * 	make a deep copy of this packet
 */

struct packet * packet_duplicate(const struct packet * p)
{
	assert(p->magic==PACKET_MAGIC);
	packet * new_p = malloc_and_test(sizeof(struct packet));
	memcpy(new_p,p,sizeof(struct packet));
	new_p->refcount=1;
	if(p->ip_opts)
	{
		new_p->ip_opts = malloc_and_test(p->ip_opt_len);
		assert(new_p->ip_opts);
		memcpy(new_p->ip_opts,p->ip_opts,p->ip_opt_len);
		new_p->ip_opt_len=p->ip_opt_len;
	}
	if(p->tcp_opts)
	{
		new_p->tcp_opts = malloc_and_test(p->tcp_opt_len);
		assert(new_p->tcp_opts);
		memcpy(new_p->tcp_opts,p->tcp_opts,p->tcp_opt_len);
		new_p->tcp_opt_len=p->tcp_opt_len;
	}
	if(p->data)
	{
		new_p->data = malloc_and_test(p->datalen);
		assert(new_p->data);
		memcpy(new_p->data,p->data,p->datalen);
		new_p->datalen=p->datalen;
	}
	return new_p;
}

/*******************************************************************************
 * static int recalc_sizes(struct packet *p);
 * 	fixup the ip and tcp headers to make sure all of the sizes correspond to the
 * 	data stored
 */

int recalc_sizes(struct packet *p)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	switch(p->type)
	{
		case IPPROTO_TCP:
			assert((p->tcp_opt_len%4)==0);
			p->tcp.doff=(sizeof(struct tcphdr)+p->tcp_opt_len)/4;	// small than 1 byte, no htons()
			p->ip.ihl = (sizeof(struct iphdr)+p->ip_opt_len)/4;	// small than 1 byte, no htons()
			p->ip.tot_len=htons(sizeof(iphdr)+p->ip_opt_len+sizeof(struct tcphdr)+p->tcp_opt_len+p->datalen);
			return 0;
		case IPPROTO_ICMP:
			p->ip.ihl = (sizeof(struct iphdr)+p->ip_opt_len)/4;
			p->ip.tot_len=htons(sizeof(struct iphdr)+p->ip_opt_len+sizeof(struct icmp_header)+p->datalen);
			return 0;
		default:
			sidecarlog(LOGCRIT," unknown packet type %d\n",p->type);
			abort();
	};
	return 1;	// should never get here
}
/******************************************************************************
 * static int packet_refinc(struct packet *p);
 *		increment the reference counter so that the data
 *		doesn't get trashed
 */

static int packet_refinc(struct packet *p)
{
	assert(p);
	assert(p->magic==PACKET_MAGIC);
	return p->refcount++;
}
/*****************************************************************************
 * static void packet_dump(char * buf, int len, FILE * out);
 * 	print the packet vitals to out for debugging
 */

void packet_dump(unsigned char * buf, int len, FILE * out)
{
	struct iphdr *ip;
	struct tcphdr *tcp;
	char abuf[BUFLEN];
	fprintf(out,"Packet Dump:\n");
	ip = (struct iphdr*)buf;
	tcp = (struct tcphdr *) &buf[ip->ihl*4];
	assert(ip->ihl*4<len);
	fprintf(out,
			"ip->ihl: %d\n"
			"ip->version: %d\n"
			"tos %d\n"
			"tot_len %d\n"
			"id %d\n"
			"frag_off %d\n"
			"ttl %d\n"
			"protocol %d\n"
			"check %X\n"
			"saddr %X\n"
			"daddr %X\n\n",
			ip->ihl,
			ip->version,
			ip->tos,
			ntohs(ip->tot_len),
			ip->id,
			ip->frag_off,
			ip->ttl,
			ip->protocol,
			ip->check,
			ip->saddr,
			ip->daddr);
	fprintf(out,
			" source %d\n"
			" dest %d\n"
			" seq %X\n"
			" ack_seq %X\n"
			" res1:4 %d\n"
			" doff:4 %d\n"
			" fin:1 %d\n"
			" syn:1 %d\n"
			" rst:1 %d\n"
			" psh:1 %d\n"
			" ack:1 %d\n"
			" urg:1 %d\n"
			" res2:2 %d\n"
			" window %d\n"
			" check %X\n"
			" urg_ptr %X\n",
			ntohs(tcp->source),
			ntohs(tcp->dest),
			tcp->seq,
			tcp->ack_seq,
			tcp->res1,
			tcp->doff,
			tcp->fin,
			tcp->syn,
			tcp->rst,
			tcp->psh,
			tcp->ack,
			tcp->urg,
			tcp->res2,
			ntohs(tcp->window),
			tcp->check,
			tcp->urg_ptr);
	inet_ntop(AF_INET,&ip->saddr,abuf,BUFLEN);
	fprintf(out,"Src ip = %s\n",abuf);
	inet_ntop(AF_INET,&ip->daddr,abuf,BUFLEN);
	fprintf(out,"Dst ip = %s\n",abuf);
	fprintf(out,"len = %d : iphdr = %d tcphdr = %d data =%d tot=%d\n",
			len, ip->ihl*4,tcp->doff*4,ntohs(ip->tot_len)-(4*(ip->ihl+tcp->doff)),ntohs(ip->tot_len));
}


/************************************************************
 * snagged and modified from from http://e.wheel.dk/~jesper/traceroute.diff
 * 	return 1 if mpls field has been filed in, 0 otherwise
 */

static int decode_mpls_extensions(u_char *buf, int ip_len, struct mpls_header *mpls)
{
	struct icmp_ext_cmn_hdr *cmn_hdr;
	struct icmp_ext_obj_hdr *obj_hdr;
	int datalen, obj_len;
	u_int32_t mpls_h;
	struct ip *ip;

	ip = (struct ip *)buf;

	if (ip_len <= (ip->ip_hl << 2) + ICMP_EXT_OFFSET) {
		/*
		 * No support for ICMP extensions on this host
		 */
		return 0;
	}

	/*
	 * Move forward to the start of the ICMP extensions, if present
	 */
	buf += (ip->ip_hl << 2) + ICMP_EXT_OFFSET;
	cmn_hdr = (struct icmp_ext_cmn_hdr *)buf;

	if (cmn_hdr->version != ICMP_EXT_VERSION) {
		/*
		 * Unknown version
		 */
		sidecarlog(LOGDEBUG_MPLS,"icmp response has header size=%d and tot_len=%d, but version %d from %x to %x offset=%d\n",
				ip->ip_hl << 2, ip_len, cmn_hdr->version,ip->ip_src.s_addr, ip->ip_dst.s_addr, (ip->ip_hl << 2) + ICMP_EXT_OFFSET);
		return 0;
	}

	datalen = ip_len - ((u_char *)cmn_hdr - (u_char *)ip);
	sidecarlog(LOGDEBUG_MPLS,"icmp response has header size=%d and tot_len=%d, data=%d, version %d from %x to %x\n",
			ip->ip_hl << 2, ip_len, datalen,cmn_hdr->version,ip->ip_src.s_addr, ip->ip_dst.s_addr);

	/*
	 * Check the checksum, cmn_hdr->checksum == 0 means no checksum'ing
	 * done by sender.
	 *
	 * If the checksum is ok, we'll get 0, as the checksum is calculated
	 * with	the checksum field being 0'd.
	 */
	if (ntohs(cmn_hdr->checksum) &&
			in_cksum((u_short *)cmn_hdr, datalen)) {

		return 0;	
	}

	buf += sizeof(*cmn_hdr);
	datalen -= sizeof(*cmn_hdr);

	while (datalen > 0) {
		obj_hdr = (struct icmp_ext_obj_hdr *)buf;
		obj_len = ntohs(obj_hdr->length);

		/*
		 * Sanity check the length field
		 */
		if (obj_len > datalen) {
			return 0;
		}

		datalen -= obj_len;

		/*
		 * Move past the object header
		 */
		buf += sizeof(struct icmp_ext_obj_hdr);
		obj_len -= sizeof(struct icmp_ext_obj_hdr);

		switch (obj_hdr->class_num) {
			case MPLS_STACK_ENTRY_CLASS:
				switch (obj_hdr->c_type) {
					case MPLS_STACK_ENTRY_C_TYPE:
						while (obj_len >= sizeof(u_int32_t)) {
							mpls_h = ntohl(*(u_int32_t *)buf);

							buf += sizeof(u_int32_t);
							obj_len -= sizeof(u_int32_t);

							//mpls = (struct mpls_header *) &mpls_h;
							assert(sizeof(struct mpls_header) == sizeof(mpls_h));
							memcpy(mpls,&mpls_h,sizeof(struct mpls_header));
							/* 
							 * printf("\n     MPLS Label=%d CoS=%d TTL=%d S=%d",
							 *      mpls->label, mpls->exp, mpls->ttl, mpls->s);
							 */
							sidecarlog(LOGDEBUG_MPLS,"found mpls trailer: %x to %x: l=%d, e=%d, ttl=%d s=%d\n",
									ip->ip_src.s_addr, ip->ip_dst.s_addr, mpls->label, mpls->exp, mpls->ttl, mpls->s);
							return 1;
						}
						if (obj_len > 0) {
							/*
							 * Something went wrong, and we're at a unknown offset
							 * into the packet, ditch the rest of it.
							 */
							return 0;
						}
						break;
					default:
						/*
						 * Unknown object, skip past it
						 */
						buf += ntohs(obj_hdr->length) -
							sizeof(struct icmp_ext_obj_hdr);
						break;
				}
				break;

			default:
				/*
				 * Unknown object, skip past it
				 */
				buf += ntohs(obj_hdr->length) -
					sizeof(struct icmp_ext_obj_hdr);
				break;
		}
	}
	return 1;	// we really did find an MPLS header and it's valid
}

/*******************************************************************************
 * int packet_tag_icmp_with_connection(packet * p, connection * con)
 * 	make this icmp packet with data s.t. we can map it back to the
 * 	connection it came from; meant from ICMP_ECHO and ICMP_ECHORESP
 * 	put pid() into echo.id, put a unique echo id tagged to our connection in the seq field
 */

int packet_tag_icmp_ping_with_connection(packet * p, connection * con)
{
	static u16 UniqueId=1;
	void * key;
	assert(p->magic==PACKET_MAGIC);
	assert(con->magic==CONMAGIC);
	p->icmp.un.echo.id = htons(getpid());
	p->icmp.un.echo.sequence = htons(UniqueId);
	key = pmdb_echoidcache_echo2data(UniqueId);
	pmdb_insert(SidecarCtx->echoidcache,key,con);
	sidecarlog(LOGDEBUG," tagging packet ip.id=%d echo.id=%d echo.seq=%d as with con %d\n",
			p->ip.id, getpid(),UniqueId,con->id);
	UniqueId++;
/*
 * 	// OLD Scheme .. very dumb
	count = strlen(CON_MAGIC_STR)+1
		+sizeof(SidecarCtx->localIP)
		+sizeof(con->lport)
		+sizeof(con->remoteIP)
		+sizeof(con->rport);
	assert(BUFLEN>=count);
	snprintf(buf,BUFLEN,"%s",CON_MAGIC_STR);
	ptr=buf;
	ptr+=strlen(CON_MAGIC_STR)+1;
	memcpy(ptr,&SidecarCtx->localIP,sizeof(SidecarCtx->localIP));
	ptr+=sizeof(SidecarCtx->localIP);
	memcpy(ptr,&con->lport,sizeof(con->lport));
	ptr+=sizeof(con->lport);
	memcpy(ptr,&con->remoteIP,sizeof(con->remoteIP));
	ptr+=sizeof(con->remoteIP);
	memcpy(ptr,&con->rport,sizeof(con->rport));
	ptr+=sizeof(con->rport);
	// if too small, allocate and write
	if(p->datalen<count)
		packet_set_data(p,buf,count);
	else	// else just write
		memcpy(p->data,buf,count);
		*/

	return 0;
}
