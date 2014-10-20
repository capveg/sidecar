#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/ip_icmp.h>

#include "connections.h"
#include "context.h"
#include "log.h"
#include "sidecar.h"
#include "pmdb.h"
#include "pmdb_echoidcache.h"


static int update_old_data(struct connection * con, struct iphdr *,struct tcphdr *tcp);
static connection * connection_lookup_by_icmp_ping(struct tapcontext *ctx, iphdr *ip, struct icmp_header *,int len);
static connection * connection_lookup_by_icmp_in_icmp(struct tapcontext *ctx, iphdr *ip, iphdr * real_ip,int len);
// static connection * connection_lookup_by_id(int);

char * connection_statestr[]={
"UNKNOWN",
"SYNSENT",
"SYNACKSENT",
"CONNECTED",
"CLOSED",
"TIMEWAIT",
"REMOTECLOSE"
};

struct timestamp_bucket	// used to store timestamps, for RTT calculations
{
	u32 value;
	struct timeval sentTime;
	struct timestamp_bucket * next, *prev;
};

static int ConnectionID=0;
static int IP_ID_COUNTER=0;

/******************************************************************
 * connection * connection_create(struct tapcontext *, unsigned int dstip, unsigned short dport);
 * 	create a connection struct, fill in values, insert into the hash lookup table
 */

connection * connection_create(struct tapcontext *ctx, iphdr *ip, tcphdr *tcp)
{
	connection *c;
	unsigned int remoteip,lseq,rseq;
	unsigned short rport,lport;
	unsigned short hash;
	char remoteIPbuf[BUFLEN];
	int lwindow,rwindow;
	int srcIsRemote;

	if(tcp->rst || tcp->fin)
		return NULL;		// don't create connections where the first packet we see
					// is a fin or rst
	if((!tcp->syn)&&(ntohs(ip->tot_len)==((ip->ihl+tcp->doff)*4)))
		return NULL;		// don't start a new connection until we see data or a syn packet
					// this prevents spurious connections being created from the final
					// part of a three way close

	c = (connection *) malloc_and_test(sizeof(connection));
	if(c==NULL)
	{
		perror("connection_create::malloc");
		abort();
	}
	memset(c,0,sizeof(connection));
	if(ip->saddr == ctx->localIP)
	{
		remoteip=ip->daddr;
		rport=ntohs(tcp->dest);
		lport=ntohs(tcp->source);
		lseq = ntohl(tcp->seq);
		rseq = ntohl(tcp->ack_seq);
		lwindow=ntohs(tcp->window);
		c->l_ip_id=ip->id;		// don't switch to host byte order
		c->ackrecved=0;		 
		rwindow=-1;
		srcIsRemote=0;
	} else {
		remoteip=ip->saddr;
		rport=ntohs(tcp->source);
		lport=ntohs(tcp->dest);
		lseq = ntohl(tcp->ack_seq);
		rseq = ntohl(tcp->seq);
		rwindow=ntohs(tcp->window);
		c->l_ip_id=0;			
		if(tcp->ack)
			c->ackrecved=ntohl(tcp->ack_seq);
		lwindow=-1;
		srcIsRemote=1;
	}
	// fill in values
	c->magic=CONMAGIC;
	c->remoteIP=remoteip;
	c->rport=rport;
	c->lport=lport;
	c->lSeq=lseq;
	c->rSeq=rseq;
	c->refcount=1;
	c->lWindow=MAX(lwindow,0);
	c->rWindow=MAX(rwindow,0);
	c->idletimerId=-1;	// no idle timer yet
	c->idletimeout=0;	// no idle timer yet
	if(srcIsRemote)
		c->remoteTTL=ip->ttl;
	else
		c->remoteTTL=-1;	// needs to be set latter
	c->oldDataMax=CONNECTION_DEFAULT_OLD_DATA;	// circular buffer
	c->oldData = malloc_and_test(c->oldDataMax);
	assert(c->oldData);
	c->oldDataIndex=c->oldDataFull=0;
	c->timewaitCallback=NULL;
	c->icmpInCallback=NULL;
	c->icmpOutCallback=NULL;
	c->inpacketsCallback=NULL;
	c->outpacketsCallback=NULL;
	c->closedconnectionCallback=NULL;
	c->tsb_head=c->tsb_tail=NULL;
	c->mostRecentTimestamp=0;
	c->rtt=c->rtt_estimates=0;		// zero rtt info
	c->mdevrtt=3000000;			// TCP Illustrated Vol I, p. 305, 
						// init mdev=3seconds
	memset(c->probeTracking,0,NPROBES);	// zero probe tracking data
#ifdef REENTRANT
	c->lock = (pthread_mutex_t *) malloc_and_test(sizeof(pthread_mutex_t));
	assert(c->lock);
	pthread_mutex_init(c->lock,NULL);
#endif
	if(tcp->syn)
	{
		if(tcp->ack)
			c->state=SYNACKSENT;
		else 
			c->state=SYNSENT;
	} else
		c->state=CONNECTED;

	hash = mkhash(remoteip,rport);
	// add to hash list
#ifdef REENTRANT
	pthread_mutex_lock(ctx->lock);
#endif
	c->next = ctx->connections[hash];
	ctx->connections[hash]=c;
	// add to connection list
	c->connext = ctx->conhead;
	c->conprev=NULL;
	if(c->connext)
		c->connext->conprev=c;
	ctx->conhead = c;
#ifdef REENTRANT
	pthread_mutex_unlock(ctx->lock);
#endif
	c->id=ConnectionID++;
	// log and return
	inet_ntop(AF_INET,&remoteip,remoteIPbuf,BUFLEN);
	sidecarlog(LOGDEBUG,"New connection from %s:%d state %s :: con id %d\n",remoteIPbuf,rport,connection_statestr[c->state], c->id);
	SidecarCtx->nOpenConnections++;
	return c;
}

/****************************************************************
 * int connection_inc_ref(struct connection * con);
 * 	increment the refernce counter for making a copy of the connection
 */
int connection_inc_ref(struct connection * con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	sidecarlog(LOGDEBUG2," connection id %d inc: new refcount %d\n",con->id,++con->refcount);
	return con->refcount;
}

/****************************************************************
 * int mkhash(unsigned int ip, unsigned short port);
 * 	hash the three bytes, and return something in [0,HASHSIZE]
 */

int mkhash(unsigned int ip, unsigned short port)
{
	unsigned short hash;
	hash = ((ip &0xffff0000)>>16)^(ip&0x0000ffff)^port;
	return hash;
}

/****************************************************************
 * connection * connection_lookup(tapcontext *, unsigned int dstip, unsigned short dst port);
 *	look in the linked list at ctx->connections[hash] to see if a connection matching the dstip:dport pair exists
 *	if yes, return it
 *	if no, return NULL
 */

connection * connection_lookup(tapcontext *ctx, iphdr *ip, tcphdr *tcp)
{
	connection * c;
	unsigned int remoteip;
	unsigned short rport;
	unsigned short hash;
	if(ip->saddr == ctx->localIP)
	{
		remoteip=ip->daddr;
		rport = ntohs(tcp->dest);
	} else {
		remoteip=ip->saddr;
		rport = ntohs(tcp->source);
	}
       
	hash	= mkhash(remoteip,rport);
	c = ctx->connections[hash];
#ifdef REENTRANT
	pthread_mutex_lock(ctx->lock);
#endif
	while(c)
	{
		if((c->remoteIP == remoteip)&&(c->rport==rport))
			break;
		c= c->next;
	}
#ifdef REENTRANT
	pthread_mutex_unlock(ctx->lock);
#endif
	if(c)
		assert(c->magic==CONMAGIC);
	return c;	// either we found it, and this is valid, or we didn't find, and it's NULL
}

/****************************************************************
 * connection * connection_lookup_by_icmp(struct tapcontext *, iphdr *ip);
 * 	delve into the icmp packet and look up 
 *	in the linked list at ctx->connections[hash] to see if a connection matching the dstip:dport pair exists
 *	if yes, return it
 *	if no, return NULL
 *
 */

connection * connection_lookup_by_icmp(struct tapcontext *ctx, iphdr *ip, int len)
{
	connection * c;
	struct icmp_header * icmp;
	struct tcphdr *tcp;
	struct iphdr *real_ip;
	unsigned int remoteip;
	unsigned short rport;
	unsigned short hash;
	char srcbuf[BUFLEN],dstbuf[BUFLEN];

	inet_ntop(AF_INET,&ip->saddr,srcbuf,BUFLEN);
	inet_ntop(AF_INET,&ip->daddr,dstbuf,BUFLEN);
	icmp = (struct icmp_header *)((unsigned char *)ip+ ip->ihl*4);
	if((icmp->type == ICMP_ECHO)||(icmp->type == ICMP_ECHOREPLY))
		return connection_lookup_by_icmp_ping(ctx,ip,icmp,len);	// special case
	if((icmp->type !=ICMP_TIME_EXCEEDED)&&(icmp->type!=ICMP_DEST_UNREACH)&&(icmp->type!=ICMP_PARAMETERPROB))
	{
		sidecarlog(LOGCRIT,"connection_lookup_by_icmp:: got icmp type,code= %d %d; from %s to %s handling not implemented\n",
				icmp->type,icmp->code, srcbuf,dstbuf);
		return NULL;
	}
	if(len < (2*sizeof(struct iphdr)+8+8))	// 2 ip headers + 8 byte icmp + 8 bytes of ip payload
	{
		sidecarlog(LOGDEBUG,"connection_lookup_by_icmp:: from %s to %s the captured packet length %d is less than %d: bad!\n",
				srcbuf,dstbuf,len, 2*sizeof(struct iphdr)+4+8);
		return NULL;
	}
	
	real_ip = (struct iphdr *)((unsigned char*) icmp + 8);	// 8 is the magic offset into the ICMP data
	if(real_ip->protocol == IPPROTO_ICMP)
		return connection_lookup_by_icmp_in_icmp(ctx,ip,real_ip,len);
	if(real_ip->protocol != IPPROTO_TCP)		// don't know how to handle anything else
	{
		sidecarlog(LOGCRIT,"weird: got an icmp response (type=%d,code=%d) from a ipprot %d packet\n",
				icmp->type,icmp->code,real_ip->protocol);
		return (connection *)NULL;
	}
	tcp = (struct tcphdr *)((unsigned char*) real_ip +4*real_ip->ihl);
	// now real_ip and tcp should point to the *bounced* packet's ip and tcp headers
	// NOTE that only the first 8 bytes of the tcp header are valid, but that is all we need
	
	if(real_ip->saddr == ctx->localIP)
	{
		remoteip=real_ip->daddr;
		rport = ntohs(tcp->dest);
	} else {
		remoteip=real_ip->saddr;
		rport = ntohs(tcp->source);
	}
       
	hash	= mkhash(remoteip,rport);
	c = ctx->connections[hash];
#ifdef REENTRANT
	pthread_mutex_lock(ctx->lock);
#endif
	while(c)
	{
		if((c->remoteIP == remoteip)&&(c->rport==rport))
			break;
		c= c->next;
	}
#ifdef REENTRANT
	pthread_mutex_unlock(ctx->lock);
#endif
	if(c)
		assert(c->magic==CONMAGIC);
	else
	{
		sidecarlog(LOGDEBUG," got ICMP packet for unknown connection from %s to %s\n",
				                                        srcbuf,dstbuf);
	}
	return c;	// either we found it, and this is valid, or we didn't find, and it's NULL
}
/***************************************************************************************************** 
 * static connection * connection_lookup_by_icmp_in_icmp(struct tapcontext *ctx, iphdr *ip, iphdr * real_ip,int len);
 * 	we have an ICMP time-exceeded style bounce of an ICMP packet;
 * 	look for packet_tag_by_connection() markings
 */

static connection * connection_lookup_by_icmp_in_icmp(struct tapcontext *ctx, iphdr *ip, iphdr * real_ip,int len)
{
	struct icmp_header * icmp;
	char srcbuf[BUFLEN],dstbuf[BUFLEN];
	connection * c;
	int id;
	void * key;

	inet_ntop(AF_INET,&ip->saddr,srcbuf,BUFLEN);
	inet_ntop(AF_INET,&ip->daddr,dstbuf,BUFLEN);
	icmp = (struct icmp_header *)((unsigned char *)real_ip + real_ip->ihl*4);

	if(icmp->un.echo.id != ntohs(getpid()))
	{
		sidecarlog(LOGDEBUG," ignoring non-pid matching ICMP packet in ICMP"
				" bounce for unknown connection from %s to %s\n",
			                                        srcbuf,dstbuf);
		return NULL;
	}
	id = ntohs(icmp->un.echo.sequence);
	key = pmdb_echoidcache_echo2data(id);
	c = (connection *)pmdb_lookup(SidecarCtx->echoidcache,key);
	if(c)
	{
		// pmdb_delete(SidecarCtx->echoidcache,key);		// we will see it twice; don't delete(not sure what to do: is mem leak)
		assert(c->magic==CONMAGIC);
	}
	else
	{
		sidecarlog(LOGDEBUG," got ICMP packet in ICMP bounce for unknown connection from %s to %s: echo.seq=%d\n",
				                                        srcbuf,dstbuf,id);
	}
	free(key);
	return c;	// either we found it, and this is valid, or we didn't find, and it's NULL


}
/****************************************************************
 * connection * connection_lookup_by_icmp_ping(struct tapcontext *, iphdr *ip,struct icmp_header *icmp, int len);
 * 	delve into the icmp packet payload, and match on CON_MAGIC_STR
 *	to look for connection in ctx->connections[hash] to see if a connection matching the dstip:dport pair exists
 *	if yes, return it
 *	if no, return NULL
 *
 *		
 *
 */

connection * connection_lookup_by_icmp_ping(struct tapcontext *ctx, iphdr *ip,struct icmp_header *icmp, int len)
{
	pid_t pid;
	connection * c;
	char srcbuf[BUFLEN],dstbuf[BUFLEN];
	int id;
	void *key;

	inet_ntop(AF_INET,&ip->saddr,srcbuf,BUFLEN);
	inet_ntop(AF_INET,&ip->daddr,dstbuf,BUFLEN);
	pid = getpid();
	if( pid != ntohs(icmp->un.echo.id))
	{
		sidecarlog(LOGDEBUG,"connection_lookup_by_icmp:: ignoring PING packets from %s to %s type=%d code=%d: pid %d != id %d\n",
				srcbuf,dstbuf,icmp->type,icmp->code,pid,ntohs(icmp->un.echo.id));
		return NULL;
	}

	id = ntohs(icmp->un.echo.sequence);
	key = pmdb_echoidcache_echo2data(id);
	c = (connection *)pmdb_lookup(SidecarCtx->echoidcache,key);

	if(c)
	{
		// pmdb_delete(SidecarCtx->echoidcache,key);
		assert(c->magic==CONMAGIC);
	}
	else
	{
		sidecarlog(LOGDEBUG," got ICMP PING packet for unknown connection from %s to %s echo.seq=%d id=%d(%d)\n", 
				srcbuf,dstbuf,id,ntohs(ip->id),ip->id);
	}
	free(key);
	return c;	// either we found it, and this is valid, or we didn't find, and it's NULL
}
/******************************************************************************************
 * int connection_update(struct tapcontext *, connection *c, iphdr *ip,tcphdr * tcp);
 * 	update the given connection's information given a new packet
 * 		return 1 if the state has changed
 * 		else return 0
 * 	FIXME: PAWS
 */

int connection_update(struct tapcontext *ctx,connection * c, iphdr *ip,tcphdr * tcp)
{
	unsigned int lseq, rseq;
	int lwindow, rwindow;
	int oldstate;
	char remoteIPbuf[BUFLEN];
	int sourceIsLocal;
	assert(c != NULL);
	assert(c->magic==CONMAGIC);
	lwindow=rwindow=-1;
	// we have a valid existing connection in c
	// figure out which side is local/remote
	if((ip->saddr == ctx->localIP)&&(ntohs(tcp->source)==c->lport))
	{
		lseq=ntohl(tcp->seq)+ntohs(ip->tot_len)-4*(ip->ihl+tcp->doff);	// SEQ+datalen
		rseq=ntohl(tcp->ack_seq);
		lwindow=ntohs(tcp->window);
		sourceIsLocal=1;
		c->l_ip_id=ip->id;		// don't switch to host byte order
	} 
	else 
	{
		rseq=ntohl(tcp->seq)+ntohs(ip->tot_len)-4*(ip->ihl+tcp->doff);  // SEQ+datalen
		lseq=ntohl(tcp->ack_seq);
		rwindow=ntohs(tcp->window);
		if((tcp->ack)&&(ntohl(tcp->ack_seq)>c->ackrecved))
			c->ackrecved=ntohl(tcp->ack_seq);	// they acked new data
								// FIXME not sure how to handle PAWS here
		sourceIsLocal=0;
		if(c->remoteTTL==-1)
			c->remoteTTL=ip->ttl;				// this hasn't been set yet
	}
	// save old state
	oldstate=c->state;
	if(c->state==CLOSED)				// don't do any further updates on closed connections
		return 0;

	// update sequence space
	if(lseq>c->lSeq)
	{
		c->lSeq=lseq;
		if(lwindow!=-1)
			c->lWindow=lwindow;
		if(sourceIsLocal)			// copy any new data to a buffer for reuse later
			update_old_data(c,ip,tcp);
	}
	if(sourceIsLocal && c->oldDataIndex==0)	// HACK: what can happen on planetlab is packets 
		update_old_data(c,ip,tcp);		// arrive out of order, so the ACK for the data
							// can arrive before the data, preventing the
							// block before this from getting called
	if(rseq>c->rSeq)
	{
		c->rSeq=rseq;
		if(rwindow!=-1)
			c->rWindow=rwindow;
	}
	// shortcut rst flag handling
	// 	always just go to CLOSED
	if(tcp->rst )
	{
		c->state = CLOSED;
		inet_ntop(AF_INET,&c->remoteIP,remoteIPbuf,BUFLEN);
		if(!sourceIsLocal)
		{
			sidecarlog(LOGDEBUG,"Closing connection %d by RST from %s:%d: newstate %s oldstate %s\n",
					c->id,remoteIPbuf,c->rport,connection_statestr[c->state],
					connection_statestr[oldstate]);
		}
		else
		{
			sidecarlog(LOGDEBUG,"Closing connection %d by local RST sent to %s:%d: newstate %s oldstate%s\n",
					c->id,remoteIPbuf,c->rport,connection_statestr[c->state], connection_statestr[oldstate]);
		}
		return c->state!=oldstate;	// if the connection just closed, return 1, otherwise 0
	}
	// shortcut fin flag handling
	//  	IF sourceIsLocal 
	//  		IF oldstate==REMOTECLOSE,  go to TIMEWAIT
	//  		ELSE go to CLOSED
	//   	ELSE
	//   		go to REMOTECLOSE
	if(tcp->fin )
	{
		inet_ntop(AF_INET,&c->remoteIP,remoteIPbuf,BUFLEN);
		if(sourceIsLocal)
		{
			if((oldstate==REMOTECLOSE)||(oldstate==TIMEWAIT))
				c->state=TIMEWAIT;	// if remote previously init'd the close, then go to the timewait state
							// this could also be an outgoing FIN|ACK probe
			else
				c->state=CLOSED;	// else, just shut everything down
			sidecarlog(LOGDEBUG,"Closing connection %d by Local FIN sent to %s:%d: new state %s oldstate %s\n",
					c->id,remoteIPbuf,c->rport,connection_statestr[c->state],
					connection_statestr[oldstate]);
		}
		else
		{	// we have short cutted CLOSED connections, so we only end up here if remote init'ed close
			assert(c->state!=CLOSED);
			c->state=REMOTECLOSE;
			sidecarlog(LOGDEBUG,"Received remote FIN from %s:%d: con id %d :  new state %s oldstate %s\n",
					remoteIPbuf,c->rport,c->id,connection_statestr[c->state],
					connection_statestr[oldstate]);
		}
		return (c->state!=oldstate); // if the state changed, return 1, else 0
	}

	// State transitions for all non-RST/FIN packets
	switch(c->state)
	{
		case SYNSENT:
			if(tcp->syn && tcp->ack)
				c->state=SYNACKSENT;
			if(!tcp->syn && tcp->ack)	// must have missed the SYN|ACK and ACK
				c->state=CONNECTED;
			break;
		case SYNACKSENT:
			if(!tcp->syn && tcp->ack)
				c->state=CONNECTED;
			break;
		case REMOTECLOSE:		// remote close is a half close from the remote
						// we can still send data, so do same as CONNECTED
		case CONNECTED:
			// FIN and RST have already been handled, just record outgoing data
			break;
		case TIMEWAIT:
			// we don't need to update anything else when in timewait
			break;
		case CLOSED:
			// should never get here, we short cutted CLOSED connections
			abort();
			break;
		default:
			inet_ntop(AF_INET,&c->remoteIP,remoteIPbuf,BUFLEN);
			sidecarlog(LOGCRIT,"ABORT: unknown state %d for %s:%d\n",
					c->state,remoteIPbuf,c->rport);
			abort();
	};

	inet_ntop(AF_INET,&c->remoteIP,remoteIPbuf,BUFLEN);
	if(c->state!=oldstate)
	{
		sidecarlog(LOGDEBUG,"update for %s:%d new state %s\n",remoteIPbuf,c->rport,connection_statestr[c->state]);
	} else
	{
		sidecarlog(LOGDEBUG,"update for %s:%u -- %u:%u\n",remoteIPbuf,c->rport,c->lSeq,c->rSeq);
	}

	return c->state!=oldstate;
}

/*******************************************************************
 * int connection_free(struct tapcontext *, connection *);
 * 	decr reference count
 * 	if zero, remove from hashlist, free mem
 */

int connection_free(tapcontext * ctx, connection *c)
{
	unsigned short hash;
	connection * parent,*tmp;
	char remoteIPbuf[BUFLEN];
	void (*fun)(void *);
	void *arg;
	struct timestamp_bucket *tsb,*tmptsb;
	assert(c);
	assert(ctx);
	assert(c->magic==CONMAGIC);
	c->refcount--;
	sidecarlog(LOGDEBUG2," connection id %d free: new refcount %d\n",c->id,c->refcount);
	if(c->refcount>0)	// the bell does not toll for this one...
		return 0;
	// needs to be removed
	if(c->closedconnectionCallback)	// this should be a redundant closeCB()
	{
		sidecarlog(LOGDEBUG," calling closedconnectionCallback\n");
		c->closedconnectionCallback(c);	// this should free c->appData
		sidecarlog(LOGDEBUG," return from closedconnectionCallback\n");
		c->closedconnectionCallback=NULL;
	}
	hash = mkhash(c->remoteIP,c->rport);
	parent=NULL;
#ifdef REENTRANT
	pthread_mutex_lock(ctx->lock);
#endif
	tmp = ctx->connections[hash];
	while(tmp!=NULL)
	{
		if((tmp->remoteIP==c->remoteIP)&&(tmp->rport==c->rport))
			break;
		parent=tmp;
		tmp=tmp->next;
	}
	if(tmp==NULL)
	{
#ifdef REENTRANT
		pthread_mutex_unlock(ctx->lock);
#endif
		inet_ntop(AF_INET,&c->remoteIP,remoteIPbuf,BUFLEN);
		sidecarlog(LOGCRIT,"ABORT: tried to delete non-existant connection %s:%d in state %s\n",
				remoteIPbuf,c->rport,connection_statestr[c->state]);
		abort();
	}
	// remove from hash bucket
	if(parent!=NULL)
		parent->next=c->next;
	else
		ctx->connections[hash]=c->next;
#ifdef REENTRANT
	pthread_mutex_unlock(ctx->lock);
	free(c->lock);
#endif
	// remove from iterative connections list
	if(c->connext)		// if we have someone after us
	{
		if(c->conprev)	// if there is someone before us
		{
			c->conprev->connext=c->connext;
			c->connext->conprev=c->conprev;
		}
		else
		{
			SidecarCtx->conhead=c->connext;
			c->connext->conprev=NULL;
		}
	} 
	else
	{	// we are at the end 
		if(c->conprev)	// if there is someone before us
			c->conprev->connext=NULL;
		else
			SidecarCtx->conhead=NULL;	// we really are the last one
	}
	if(c->idletimerId)
		wc_event_remove(SidecarCtx->timers,c->idletimerId,&fun,&arg);
    /* should be replaced with a deep free, or left to that which stored
       the app data to disard -nspring  

       - capveg: commented out all together: the application should
		handle this in the closeconnectionCallback() and the
		free() here will most likely result in a double free()
		with corruption
	if(c->appData)
		free(c->appData);
     */
	probe_cache_flush(c);
	tsb=c->tsb_head;
	while(tsb)
	{
		tmptsb=tsb;
		tsb=tsb->next;
		free(tmptsb);
	}
	SidecarCtx->nOpenConnections--;
	free(c->oldData);
	free(c);
	return 0;
}

/************************************************************************************
 * int connection_get_id(struct connection*);
 * 	return c->id; unique connection identifier;
 * 		in practice it's just a counter, but should be okay
 */
int connection_get_id(struct connection* con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	return con->id;
}

/************************************************************************************
 * int connection_get_name(struct connection*, char * name, int * namelen);
 * 	return "sip:sport-dip:dport" string based on the connection
 */

int connection_get_name(struct connection* con, char * name, int * namelen)
{
	int len;
	char buf[BUFLEN];
	char src[BUFLEN];
	assert(con);
	assert(con->magic==CONMAGIC);
	inet_ntop(AF_INET,&con->remoteIP,buf,BUFLEN);
	inet_ntop(AF_INET,&SidecarCtx->localIP,src,BUFLEN);
	len=snprintf(name,*namelen,"%s:%u-%s:%u",src,con->lport,buf,con->rport);
	name[*namelen-1]=0;	// force a NULL if snprintf was short
	*namelen=len;
	return len;
}

/**********************************************************************************
 * struct packet * connection_make_packet(struct connection *);
 * 	Given a connection, create an zero-data packet with the current
 * 	sequence/ack numbers and ip/port info for the given connection
 * 	from the local host to the remote host; don't fill in checksum, as that
 * 	will happen on send
 */

struct packet * connection_make_packet(struct connection * con)
{
	struct tcphdr tcp;
	struct iphdr ip;
	packet * p;

	assert(con->magic==CONMAGIC);
	p = packet_create();
	memset(&ip,0,sizeof(ip));
	memset(&tcp,0,sizeof(tcp));
	// fill in ip header
	ip.ihl=5;
	ip.version=4;
	ip.tos=0;
	ip.id= IP_ID_COUNTER++;
	ip.frag_off=htons(0x4000);	// don't fragment, network byte order
	ip.ttl= SidecarCtx->ttl;
	ip.protocol=IPPROTO_TCP;
	ip.check = 0;
	ip.saddr = SidecarCtx->localIP;
	ip.daddr = con->remoteIP;
	packet_set_ip_header(p,&ip);
	// fill in tcp header
	tcp.source = htons(con->lport);
	tcp.dest = htons(con->rport);
	tcp.doff=5;
	tcp.ack=1;
	tcp.seq = htonl(con->lSeq);
	tcp.ack_seq = htonl(con->rSeq);
	tcp.window  = htons(con->lWindow);
	packet_set_tcp_header(p,&tcp);
	
	return p;
}

/*********************************************************************************
 * void * connection_set_app_data(struct connection *,void *data );
 * 	set the application specific data pointer to data
 * 	return the old value
 */

void * connection_set_app_data(struct connection * con,void *data )
{
	void * old;
	assert(con);
	assert(con->magic==CONMAGIC);
	old = con->appData;
	con->appData=data;
	return old;
}

/*****************************************************************************
 * void * connection_get_app_data(struct connection *);
 * 	return application specific data
 */

void * connection_get_app_data(struct connection * con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	return con->appData;
}

/***************************************************************************
 * int update_old_data(struct connection * con, struct iphdr *ip, struct tcphdr *tcp);
 *	cache the connection level data into a circular buffer con->oldData
 */

int update_old_data(struct connection * con, struct iphdr *ip,struct tcphdr *tcp)
{
	char * data;
	int datalen;
	int i;
	assert(con);
	assert(con->magic==CONMAGIC);
	datalen = ntohs(ip->tot_len) - (ip->ihl+tcp->doff)*4;
	if(datalen==0)
		return 0;
	if(datalen<con->oldDataMax)
	{
		sidecarlog(LOGDEBUG," update_old_data:: got datalen=%d oldDataMax=%d\n",
				datalen,con->oldDataMax);
		assert(datalen<con->oldDataMax);	// we made the buf two packets, should be easy
	}
	assert(datalen>0);
	data = ((char*)tcp)+tcp->doff*4;
	i = MIN(datalen+con->oldDataIndex,con->oldDataMax);
	memcpy(&con->oldData[con->oldDataIndex],data,i-con->oldDataIndex);	// copy until end
	if(i<datalen)	// did we wrap in the circular buffer?
	{
		con->oldDataFull=1;
		memcpy(con->oldData,&data[i],datalen-i-con->oldDataIndex); // copy rest to beginnig
	}
	con->oldDataIndex=(con->oldDataIndex+datalen)%con->oldDataMax;
	return datalen;
}

/*************************************************************************
 * unsigned int connection_get_remote_ip(struct connection *);
 * 	accessor func
 */

unsigned int connection_get_remote_ip(struct connection * con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	return con->remoteIP;
}

/**********************************************************************************
 * int connection_process_out_timestamp(struct connection *con, u32 value, struct timeval now);
 * 	save the outgoing timestamp value in a tsb so that it can be later correlated
 * 	when that value is returned
 * 		save it at the end of a doubly linked list
 */

int connection_process_out_timestamp(struct connection *con, u32 value, struct timeval now)
{
	struct timestamp_bucket *tsb;

	if(value<=con->mostRecentTimestamp)	
		return 0;	// we have already recv'ed a response for stuff after this
				// value, ignore

	tsb = malloc_and_test(sizeof(struct timestamp_bucket));
	assert(tsb!=NULL);
	tsb->value=value;
	tsb->sentTime=now;
	tsb->prev = con->tsb_tail;
	tsb->next=NULL;
	sidecarlog(LOGDEBUG_TS," con id %d :: saving timestamp %lu at time %ld.%.6ld\n",
			con->id,(u32)ntohl(value),now.tv_sec,now.tv_usec);
	// add to end of list
	if(con->tsb_tail)
	{
		con->tsb_tail->next=tsb;
		con->tsb_tail=tsb;
	} else
	{	// the list has no tail (should be empty)
		assert(con->tsb_head==NULL);
		con->tsb_head=con->tsb_tail=tsb;
	}

	return 0;
}

/************************************************************************************
 * int connection_process_in_timestamp(struct connection *con, u32 echo, struct timeval now);
 * 	extract the timestamp matching 'echo' from the connections timestamp list,
 * 	diff the times, and add it to the RTT estimator
 *
 * 	also- drop everything from the queue that happened *before* echo, b/c 
 * 	they are unlikely tobe echo'ed back -- only if there is reordering or
 * 	if the receiver is broken
 */
int connection_process_in_timestamp(struct connection *con, u32 echo, struct timeval now)
{
	struct timestamp_bucket *tsb,*tmp;
	struct timeval diff;
	long rtt_est;
	long err;
	int dels=0;

	if(echo<=con->mostRecentTimestamp)	
		return 0;	// we have already recv'ed a response for this echo 
				// (or after it), ignore
    /* nspring sayz: for(tsb=con->tsb_head; tsb != NULL && tsb->value==echo; tsb=tsb->next); */
	tsb = con->tsb_head;
	while(tsb)
	{
		if(tsb->value == echo)
			break;
		else 
			tsb=tsb->next;
	}
	if(tsb==NULL)
	{
		sidecarlog(LOGDEBUG_TS,"con id %d :: connection_process_in_timestamp:: didn't find timestamp %lu\n",
				con->id,echo);
		return 1;	// signal not found
	}
	// delete stuff before it; these will not get ACK'ed
	while(tsb->prev)
	{
		tmp=tsb->prev;
		tsb->prev=tmp->prev;
		free(tmp);
		dels++;
	}
	con->tsb_head = tsb->next;	// going to free this one as well
	// diff = diff_time(now,tsb->sentTime);
    timersub(&now, &tsb->sentTime, &diff);
	rtt_est = diff.tv_sec*1000000 + diff.tv_usec;
	// TCP/IP Illustrated Vol 1, p 300; VJCC '88
	err = rtt_est - con->rtt;
	con->rtt +=(err>>3);
	con->mdevrtt+= (labs(err)-con->mdevrtt)>>2;  // labs() == abs() for longs, who knew?
	if(con->tsb_head)
		con->tsb_head->prev=NULL;	// skip current tsb
	else 
	{
		con->tsb_head=con->tsb_tail=NULL;	// nothing left in list
	}
	con->rtt_estimates++;
	sidecarlog(LOGDEBUG_TS," con id %d :: recv timestamp %lu at time %ld.%.6ld: %d"
			" dels est = %ld : new rtt %ld mdev %ld count=%ld\n",
			con->id,(u32)ntohl(echo),now.tv_sec,now.tv_usec, dels, 
			rtt_est,con->rtt, con->mdevrtt,con->rtt_estimates);
	con->mostRecentTimestamp=echo;		// update the "mostRecent" cache
	free(tsb);
	return 0;
}

/***********************************************************************************
 * int connection_get_rtt_estimate(struct connection, long * avg, long *mdev, long * count);
 * 	just return the values from the connection struct
 */

int connection_get_rtt_estimate(struct connection * con, long * avg, long *mdev, long * count)
{
	assert(con);
	*avg=con->rtt;
	*mdev=con->mdevrtt;
	*count=con->rtt_estimates;
	return 0;
}

/***********************************************************************************
 * int connection_is_idle(struct connection *con):
 * 	return 1 if the remote host has acknowledged all of the outstanding data
 *	0 otherwise
 *
 *	FIXME: PAWS
 */

int connection_is_idle(struct connection *con)
{
	assert(con);
	if(con->ackrecved>=con->lSeq)
		return 1;
	else 
		return 0;
}

/*****************************************************************************
 * int connection_get_remote_ttl(struct connection *);
 * 	return con->remoteTTL
 * 	this value could be -1, meaning it's not initialized
 */

int connection_get_remote_ttl(struct connection * con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	return con->remoteTTL;
}

/***************************************************************************
 * int connection_count_old_data(struct connection * con)
 * 	return the amount of cached old data that is available
 */

int connection_count_old_data(struct connection * con)
{
	if(con->oldDataFull)
		return con->oldDataMax;
	else
		return con->oldDataIndex;
}

/***************************************************************************
 * int probe_add(struct connection *, u16 probe_id, void * data);
 *	add this probe to the probe tracking stuff so we can look it up later
 */

int probe_add(struct connection * con, u16 probe_id, const void * data)
{
	probedata * pd;
	int i = ((probe_id&0xff00)>>8)^(probe_id&0x00ff);	// fold the bytes on to each other

	pd = malloc_and_test(sizeof(probedata));
	assert(pd!=NULL);
	pd->id=probe_id;
	pd->data=data;
	pd->next = con->probeTracking[i];
	con->probeTracking[i] = pd;
	return 0;
}

/***************************************************************************
 * void * probe_lookup(struct connection *, u16 probe_id);
 * 	lookup the probe coresponding to this id and return the data associated with it; 
 * 	DO NOT free()
 *
 * 	return NULL if not found
 */

const void * probe_lookup(struct connection * con, u16 probe_id)
{
	probedata * pd;
	int i = ((probe_id&0xff00)>>8)^(probe_id&0x00ff);	// fold the bytes on to each other
	pd = con->probeTracking[i];
	while(pd && pd->id!=probe_id)
		pd=pd->next;
	if(pd)
		return pd->data;
	else
		return NULL;
}

/****************************************************************************
 * void * probe_delete(struct connection *, u16 probe_id);
 * 	lookup the probe corresponding to this id and return the data associated with it
 * 	(for the caller to free()).  Free up the probedata structure
 *
 * 	return NULL if not found
 */

const void * probe_delete(struct connection *con, u16 probe_id)
{
	probedata * pd,*parent;
	const void *data;
	int i = ((probe_id&0xff00)>>8)^(probe_id&0x00ff);	// fold the bytes on to each other
	parent=NULL;
	pd = con->probeTracking[i];
	while(pd && pd->id!=probe_id)
	{
		parent= pd;
		pd=pd->next;
	}
	if(pd) {
		if(parent)
			parent->next=pd->next;
		else
			con->probeTracking[i]=pd->next;
		data= pd->data;
		free(pd);
	} else {
		/* error */
		data= NULL;
		sidecarlog(LOGCRIT, "didn't find probe id %u\n", probe_id);
		abort();
	}
	return data;
}

/**************************************************************************************
 * void probe_cache_flush(struct connection *con)
 * 	free all of the cached probes b/c we are done with them
 */

void probe_cache_flush(struct connection *con)
{
	int i;
	struct probedata * prb,*prbtmp;

	for(i=0;i<NPROBES;i++)
	{
		prb = con->probeTracking[i];
		while(prb)
		{
			prbtmp=prb;
			prb=prb->next;
			free(prbtmp);
		}
		con->probeTracking[i]=NULL;
	}
}

/****************************************************************************
 * void connection_force_close(struct connection * con)
 * 	The app can signal sidecar to drop state for the connection
 * 		- needed b/c we are leaking connection state and not timeing out
 * 		- a proper solution would be for the app to register a timeout
 * 			with sidecar
 */

void connection_force_close(struct connection * con)
{
	sidecarlog(LOGDEBUG," connection %d:: force closing\n",con->id);
	con->state=CLOSED;
	connection_free(SidecarCtx,con);
}

/*****************************************************************************
 * u16 connection_get_ip_id(struct connection *);
 * 	return the most recent local->remote ip id field
 */

u16 connection_get_ip_id(struct connection * con)
{
	assert(con);
	assert(con->magic==CONMAGIC);
	return con->l_ip_id;
}

/*****************************************************************************
 * connection * connection_lookup_by_id(int);
 * 	lookup connection by id
 * 		this is going to be an O(n) lookup until it becomes
 * 		a bottleneck
 */

connection * connection_lookup_by_id(int conid)
{
	connection *c;
	c=SidecarCtx->conhead;
	while(c)
	{
		if(c->id==conid)
			break;
		c=c->connext;
	}
	return c;
}
