#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include "context.h"
#include "log.h"
#include "measurements.h"
#include "packet.h"
#include "sidecar.h"
#include "pmdb_ipcache.h"

static void read_packet(u_char *arg, const struct pcap_pkthdr *pcaph, const u_char *data);
static int getTimeStamps(struct tcphdr * tcp, u32 * value, u32 * echo);

/****************************************************************
 * int sc_do_loop();
 *	loop indefinitely on select, but set the select timeout to 
 *	be the time for the next event; should be cleaner than sigalrm
 *	especially on planetlab where signals are potentially funky
 */
int sc_do_loop()
{
	int pcap_fd;
	int err;
	int size;
	socklen_t len;
	fd_set readfds,writefds;
	struct timeval timeout;
	struct connection * con;
	struct timeval tmptime;
	int qIsEmpty=1;
	int qsize;

	verifySidecarInit();
	// pcap_fd = pcap_get_selectable_fd(SidecarCtx->handle);	// older libpcap's don't have this; just HACK around
	pcap_fd = pcap_fileno(SidecarCtx->handle);
	if(pcap_fd< 0)
	{
		sidecarlog(LOGCRIT,"sc_main_loop::pcap_get_selectable_fd returned %d instead of a valid fd\n",pcap_fd);
		return(1);
	}
	// increase the RCV buff -- see if that prevents us from dropping packets
	size = 512*1024;		// try for 512k
	len=sizeof(size);	
	err=setsockopt(pcap_fd,SOL_SOCKET,SO_RCVBUF,(void *)&size,len);
	assert(!err);

	// run initCB here
	if(SidecarCtx->initCallback)
		SidecarCtx->initCallback(SidecarCtx->initCBarg);

	len=sizeof(size);
	err=getsockopt(pcap_fd,SOL_SOCKET,SO_RCVBUF,(void *)&size,&len);
	assert(!err);

	sidecarlog(LOGINFO,"increased pcap socket rcvbuf to %d\n",size);
	// record current time
	gettimeofday(&SidecarCtx->startEmptyTime,NULL);
	timerclear(&SidecarCtx->endEmptyTime);

	// main loop
	while(!SidecarCtx->shouldStop)
	{
		// figure out how long our timeout should be
		do{
			err = wc_get_next_event_delta(SidecarCtx->timers,&timeout);	// when is next event scheduled?
			if(err == 1) // we missed an event
				wc_run_next_event(SidecarCtx->timers);
		} while(err==1);
		if(err==-1)	// if no events are scheduled
		{
			timeout.tv_sec=1;	// wait 1 sec by default (why not?)
			timeout.tv_usec=0;
		}

		// setup the pcap handle for read
		FD_ZERO(&readfds);
		FD_SET(pcap_fd,&readfds);
		// if there are packets to write, set the write handle
		FD_ZERO(&writefds);
		// only flag the send socket if we have stuff to send and we have the budget to do so
		if(!Q_Empty(SidecarCtx->outPacketQ))
		{
			if(qIsEmpty)			// did the queue just go non-empty?
			{
				qIsEmpty=0;		// then save the time, and add it to the time counter
				gettimeofday(&SidecarCtx->endEmptyTime,NULL);
				timersub(&SidecarCtx->endEmptyTime,&SidecarCtx->startEmptyTime,&tmptime);
				timeradd(&tmptime,&SidecarCtx->outPacketQEmptyTime,&SidecarCtx->outPacketQEmptyTime);
			}
			if(SidecarCtx->sendBudget>0)
				FD_SET(SidecarCtx->rawSock,&writefds);
		}
		else if(qIsEmpty==0)			// did we just empty the queue?
		{
			qIsEmpty=1;			// mark as empty and save the time
			gettimeofday(&SidecarCtx->startEmptyTime,NULL);
		}

		err = select (MAX(pcap_fd,SidecarCtx->rawSock)+1, &readfds,&writefds,NULL,&timeout);

		if(err==0)	// we timed out; just continue so the event can be run
			continue;
		if((err==-1)&&(errno==EINTR))	// we has a system call interrupt us
			continue;		// 	just move on
		if(err<0)
		{
			perror("select");	// FIXME : more graceful?
			abort();
		}
		if(FD_ISSET(pcap_fd,&readfds))
		{// read the next packet from pcap
			while((err=pcap_dispatch(SidecarCtx->handle,1,read_packet,NULL))>0);
			if(err<0)
			{
				sidecarlog(LOGCRIT,"pcap_dispatch returned %d :: %s\n",
						err,pcap_geterr(SidecarCtx->handle));
			}
		}
		if(FD_ISSET(SidecarCtx->rawSock,&writefds))
		{
			do
			{
				err=packet_send_now(SidecarCtx);		// write the next packet off the queue
			} while((err>0)&&(!Q_Empty(SidecarCtx->outPacketQ))&&(SidecarCtx->sendBudget>0));	// until we get EWOULDBLOCK/EAGAIN or out of budget
		}
		// Check to see if we should throttle or unthrottle alerting app about new connections
		qsize = Q_size(SidecarCtx->outPacketQ);
		if(qsize>SidecarCtx->outPacketQMaxLen)
		{
			if(SidecarCtx->throttleConnections==0)
				sidecarlog(LOGCRIT," qsize == %d : throttling incoming connections\n",qsize);
			SidecarCtx->throttleConnections=1;
		}
		else
		{
			if(SidecarCtx->throttleConnections==1)
				sidecarlog(LOGCRIT," qsize == %d : un-throttling incoming connections\n",qsize);
			SidecarCtx->throttleConnections=0;
		}

	}				
	// Got the signal to stop:: step through each connection and close it out
	for(con=SidecarCtx->conhead;con!=NULL;con=con->connext)
	{
		if(con->closedconnectionCallback)
		{
			con->closedconnectionCallback(con);
			con->closedconnectionCallback=NULL;	// don't close the connection twice
		}
	}

	return 0;
}


/*******************************************************************************
 * read_packet():
 * 	actually read a single packet from pcap and decide what to do with it
 */


void read_packet(u_char *arg, const struct pcap_pkthdr *pcaph, const u_char *data)
{
	struct iphdr *ip;
	struct tcphdr *tcp;
	packet *p;
	connection * con;
	char srcbuf[BUFLEN];
	char dstbuf[BUFLEN];
	int changed;
	int have_timestamps;
	u32 value, echo;	// for timestamps
	void *key;

	assert((pcaph->caplen)>sizeof(struct iphdr));	// dirty check for runt packets
	// we've already asserted we're on ethernet
	ip=(struct iphdr *)&data[14];
	inet_ntop(AF_INET,&ip->saddr,srcbuf,BUFLEN);
	inet_ntop(AF_INET,&ip->daddr,dstbuf,BUFLEN);

	if(ip->protocol == IPPROTO_ICMP)	// check to see if packet is ICMP
	{
		p= packet_make_from_buf(ip,pcaph->caplen-14);	
		con = connection_lookup_by_icmp(SidecarCtx,ip,pcaph->caplen);
		if(!con)
		{
			// no connection found:: the logging for 'why' this packet is unknown was done in connection_lookup_by_icmp()
			if(p)
				packet_free(p);
			return;
		}
		sidecarlog(LOGDEBUG," got ICMP packet from %s to %s connection\n",srcbuf,dstbuf);
		if(ip->saddr== SidecarCtx->localIP)
		{
			if((con->state!=CLOSED)&&con->icmpOutCallback) // pass all ICMP packets up to higher level, if desired
			{
				sidecarlog(LOGDEBUG," connection %d calling icmpOutCallback\n",con->id);
				con->icmpOutCallback(con,p,pcaph);
				sidecarlog(LOGDEBUG," connection %d returning from  icmpOutCallback\n",con->id);
			}
		}
		else
		{
			if((con->state!=CLOSED)&&con->icmpInCallback) // pass all ICMP packets up to higher level, if desired
			{
				sidecarlog(LOGDEBUG," connection %d calling icmpInCallback\n",con->id);
				con->icmpInCallback(con,p,pcaph);
				sidecarlog(LOGDEBUG," connection %d returning from  icmpInCallback\n",con->id);
			}
		}
		packet_free(p);
		return;
	}
	if(ip->protocol != IPPROTO_TCP)		// make sure packet is TCP
	{
		sidecarlog(LOGINFO," got a non-TCP/ICMP packet of type %d \n",
				ip->protocol);
		return;
	}
	assert(pcaph->caplen>(sizeof(struct iphdr)+sizeof(struct tcphdr)));      // dirty check for runt packets
	tcp = (struct tcphdr *) ((char *)ip+ip->ihl*4);
	con = connection_lookup(SidecarCtx,ip,tcp);
	if(con == NULL)							// if this is a new connection
	{
		if(ip->saddr== SidecarCtx->localIP)
			key = pmdb_ipcache_ip2data(ip->daddr);
		else
			key = pmdb_ipcache_ip2data(ip->saddr);
		if(pmdb_exists(SidecarCtx->ipcache,key))			// have we seen this ip before?
		{
			free(key);						// yes, just move on
			return;
		}
		else
			pmdb_insert(SidecarCtx->ipcache,key,key);		// else add it; don't free(key)
			
		if(SidecarCtx->throttleConnections)			//  return if connections are throttled
		{
			SidecarCtx->nThrottledConnections++;
			return;
		}
		con = connection_create(SidecarCtx,ip,tcp);
		if(con == NULL)
		{		// got a RST|FIN|empty packet for a non-existant connection
			sidecarlog(LOGDEBUG," ignoring RST|FIN|empty Packet without existing connection from %s:%d to %s:%d\n",
					srcbuf,ntohs(tcp->source),dstbuf,ntohs(tcp->dest));
			return;
		}

		if((con->state==CONNECTED)				// if the first time we see a packet, 
				&& SidecarCtx->connectionCallback)	// 	and they have a callback registered	
		{
			sidecarlog(LOGDEBUG," connection %d calling new connection callback on instant connection\n",con->id);
			SidecarCtx->connectionCallback(con);			// the connection is already setup, then call connectCB
			sidecarlog(LOGDEBUG," connection %d returning from new connection callback on instant connection\n",con->id);
		}
		return;
	}
	p = packet_make_from_buf(ip,pcaph->caplen-14);
	have_timestamps = getTimeStamps(tcp, &value, &echo);
	// pass the packet up to the application, if desired
	if(ip->saddr == SidecarCtx->localIP)	// if this is an outgoing packet
	{
		if(have_timestamps)
			connection_process_out_timestamp(con,value,pcaph->ts);
		if((con->state!=CLOSED) && (con->outpacketsCallback))// call outgoing packet Callback
		{
			sidecarlog(LOGDEBUG," connection %d calling out callback\n",con->id);
			con->outpacketsCallback(con,p,pcaph);
			sidecarlog(LOGDEBUG," connection %d returning from out callback\n",con->id);
		}
	} 
	else
	{
		if(have_timestamps)
			connection_process_in_timestamp(con,echo,pcaph->ts);
		if((con->state!=CLOSED) && (con->inpacketsCallback))	// else call incoming packet callback
		{
			sidecarlog(LOGDEBUG," connection %d calling in callback\n",con->id);
			con->inpacketsCallback(con,p,pcaph);
			sidecarlog(LOGDEBUG," connection %d returning from in callback\n",con->id);
		}

	}
	// the connection_update MUST happen after passing packet up for dup ack detection to work
	changed = connection_update(SidecarCtx,con,ip,tcp);	// update connection tracking information
	if(changed)					// notify app
	{	
		switch(con->state)
		{
			case TIMEWAIT:	// we end up here if connection gets a FIN
				if(con->timewaitCallback)
				{
					sidecarlog(LOGDEBUG," connection %d calling timewait callback\n",con->id);
					con->timewaitCallback(con);
					sidecarlog(LOGDEBUG," connection %d returning from timewait callback\n",con->id);
					schedule_timewait_close(con);
				}
				break;
			case CLOSED:	// this only gets called here if a connection gets an RST
				if(con->closedconnectionCallback)
				{
					sidecarlog(LOGDEBUG," connection %d calling close callback\n",con->id);
					con->closedconnectionCallback(con);
					sidecarlog(LOGDEBUG," connection %d returning from close callback\n",con->id);
					con->closedconnectionCallback=NULL;	// don't tell the app to close the connection twice
				}
				connection_free(SidecarCtx,con);	// free the connection state
								// there is ref counting in case events
								// still hold the connection state
				break;
			case CONNECTED:
				if(SidecarCtx->connectionCallback)		
				{
						sidecarlog(LOGDEBUG," connection %d calling new connection callback\n",con->id);
						SidecarCtx->connectionCallback(con);
						sidecarlog(LOGDEBUG," connection %d returning from new connection callback\n",con->id);
				}
				break;
			case SYNSENT:
			case SYNACKSENT:
			case REMOTECLOSE:
				break;
			default:
				sidecarlog(LOGCRIT," unknown connection state %d:: abort()'ing\n",con->state);
				abort();
				break;
		};
	}
	packet_free(p);
	return;
}


/********************************************************************************************
 * int getTimeStamps(struct tcphdr * tcp, unsigned int * value, unsigned int * echo )
 * 	extract the timestamp 'value' field and 'echo' fields from the tcppacket
 * 		if doesn't exist, ret 0 (tells packet_read() to ignore)
 * 		else return 1
 */

int getTimeStamps(struct tcphdr * tcp, u32 * value, u32 * echo )
{
	char * options;
	int ptr;
	char old;
	int optlen;
	assert(tcp);
	optlen = (tcp->doff*4)-sizeof(struct tcphdr);
	if(optlen<TCPOLEN_TIMESTAMP)		// too small to have timestamps
		return 0;
	options=(char *)&tcp[1];
	ptr=0;
	while(ptr<optlen)	// grr, tcp option parsing
	{
		old=ptr;
		switch(options[ptr])
		{
			// skip all options except timestamps
			case TCPOPT_NOP:
				ptr++;
				break;
			case TCPOPT_MAXSEG:
				ptr+=TCPOLEN_MAXSEG;
				break;
			case TCPOPT_WINDOW:
				ptr+=TCPOLEN_WINDOW;
				break;
			case TCPOPT_SACK_PERMITTED:
				ptr+=TCPOLEN_SACK_PERMITTED;
				break;
			case TCPOPT_SACK:
				// rfc2018
				ptr+=options[ptr+1]*8+2;	// ptr+1 is number of entries
								// each entry is 8 bytes
								// +2 for id and length
				break;
			case TCPOPT_TIMESTAMP:
				// yay! found what we were looking for
				*value = *(u32 * )&options[ptr+2];
				*echo = *(u32 * )&options[ptr+6];
				return 1;
			default:
				sidecarlog(LOGINFO,"getTimeStamps:: unknown TCP option type %d -- attempting to skip\n",options[ptr]);
				ptr++;
				break;
		};
		if((ptr<optlen) && (old == ptr))
		{
			sidecarlog(LOGCRIT," getTimeStamps:: TCP options parsing failed to make progress: loop!\n");
			abort();
		}
	}	// end while
	return 0;
}
