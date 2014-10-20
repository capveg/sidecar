#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <netinet/ip.h>


#include "passenger.h"

/***************************************************************************************************
 * struct packet ** make_recursive_packet_train(struct connection * con, int payload, int maxttl,int setRR, int *nPackets);
 * 	return an array of packets of length *nPackets
 * 		the packets go from ttl=1 to maxttl <payload packets> ttl=maxttl to 1 (RPT)
 * 		if setRR==1, then add the RR option to all packets (payload and measurement)
 *
 *
 */

struct packet ** make_recursive_packet_train(struct connection * con, trdata *tr,int *payload, int maxttl,int setRR, int * nPackets)
{
	struct packet ** packets=NULL;
	int datalen,psize;
	int nPayloadPackets;
	int i,j;
	struct iphdr ip;
	char ipoptions[MAX_IPOPTLEN];


	assert(maxttl>0);
	datalen = MIN(MSS,connection_count_old_data(con));

	if(setRR)
	{
		if((datalen+40)> MSS)
			datalen=MSS-40;	// readjust data size to fit all data + RR options in 1 packet
		psize = datalen+80;
	}
	else
		psize = datalen+40;	// no tcp options in any of these packets

	nPayloadPackets = ceil(*payload/psize);
	*payload = nPayloadPackets * psize;
	*nPackets = 2*maxttl+nPayloadPackets;
	packets = malloc(sizeof(struct packet *)* (*nPackets));
	assert(packets);

	if(setRR)
	{	// setup the ip options
		memset(ipoptions,0,MAX_IPOPTLEN);
		ipoptions[0]=IPOPT_NOP;
		ipoptions[1]=IPOPT_RR;
		ipoptions[2]=MAX_IPOPTLEN-1;
		ipoptions[3]=4;
	}

	// fill in the probes structure
	for(i=0;i<MaxSafeTTL;i++)
	{
		tr->probes[tr->iteration][i].matched=0;
		tr->probes[tr->iteration][i].status=PROBE_STATUS_SENT;
		tr->probes[tr->iteration][i].timerID=-1;
	}
	tr->nProbes[tr->iteration] = tr->nProbesOutstanding[tr->iteration]= *nPackets;

	// leading measurement packets, ttl increasing
	for(i=0;i<maxttl;i++)
	{
		packets[i]=connection_make_packet(con);	// make a packet
		packet_get_ip_header(packets[i],&ip);
		ip.ttl=i+1;
		ip.id = make_ip_id(tr,tr->iteration,i,1);
		if((tr->probeType==SYNACK_PROBE )||(tr->probeType==FINACK_PROBE))
			packet_fill_old_data(con,packets[i],1);	// sets the sequence space back 1 
							// and sets the correct flags
		packet_set_ip_header(packets[i],&ip);   // set the ip header
		if(setRR)
			packet_set_ip_options(packets[i],ipoptions,MAX_IPOPTLEN);
		tr->probes[tr->iteration][i].ttl=i+1;
		tr->probes[tr->iteration][i].type=PROBE_MARCO;
	}
	// payload packets
	for(i=0;i<nPayloadPackets;i++)
	{
		j = i+maxttl;
		packets[j]=connection_make_packet(con);
		if(datalen>0)
		{
			packet_fill_old_data(con,packets[j],datalen);
			if(tr->probeType==FINACK_PROBE)		// flip the right bits
			{
				struct tcphdr tcp;
				packet_get_tcp_header(packets[j],&tcp);
				tcp.fin=tcp.ack=1;
				packet_set_tcp_header(packets[j],&tcp);
			}
		}
		else
			packet_fill_old_data(con,packets[j],1);  // we are a SYN|ACK probesets the sequence space back 1
		                                        // and sets the correct flags
		packet_get_ip_header(packets[j],&ip);
		ip.ttl=maxttl;
		ip.id = make_ip_id(tr,tr->iteration,j,1);
		// Turn off the DF bit, so these aren't caught up in the pcap filter: DESIGN DECISION
		ip.frag_off=0;
		packet_set_ip_header(packets[j],&ip);   // set the ip header
		if(setRR)
			packet_set_ip_options(packets[j],ipoptions,MAX_IPOPTLEN);
		tr->probes[tr->iteration][j].ttl=maxttl;
		tr->probes[tr->iteration][j].type=PROBE_PAYLOAD;
	}
	// trailing measurement packets, ttl decreasing
	for(i=maxttl;i>0;i--)
	{
		j = maxttl + nPayloadPackets + (maxttl-i);
		packets[j]=connection_make_packet(con);	// make a packet
		packet_get_ip_header(packets[j],&ip);
		ip.ttl=i;
		if((tr->probeType==SYNACK_PROBE )||(tr->probeType==FINACK_PROBE))
			packet_fill_old_data(con,packets[j],1);	// sets the sequence space back 1 
							// and sets the correct flags
		ip.id = make_ip_id(tr,tr->iteration,j,1);
		packet_set_ip_header(packets[j],&ip);   // set the ip header
		if(setRR)
			packet_set_ip_options(packets[j],ipoptions,MAX_IPOPTLEN);
		tr->probes[tr->iteration][j].ttl=i;
		tr->probes[tr->iteration][j].type=PROBE_POLLO;
	}
	// sanity check
	for(i=0;i<(*nPackets);i++)
	{
		packet_get_ip_header(packets[i],&ip);
		assert(ip.ttl>0);
	}
	return packets;
}

/***************************************************************************************************
 * struct packet ** make_light_packet_train(struct connection * con, int maxttl,int setRR, int *nPackets);
 * 	return an array of packets of length *nPackets
 * 		the packets go from ttl=1 to maxttl, and use 1 data byte if PROBE_TYPE=DATA 
 * 		if setRR==1, then add the RR option to all packets 
 *
 */

struct packet ** make_light_packet_train(struct connection * con, trdata *tr,int maxttl,int setRR, int * nPackets)
{
	struct packet ** packets=NULL;
	int i;
	struct iphdr ip;
	char ipoptions[MAX_IPOPTLEN];


	assert(maxttl>0);
	*nPackets = maxttl;
	packets = malloc(sizeof(struct packet *)* (*nPackets));
	assert(packets);

	if(setRR)
	{	// setup the ip options
		memset(ipoptions,0,MAX_IPOPTLEN);
		ipoptions[0]=IPOPT_NOP;
		ipoptions[1]=IPOPT_RR;
		ipoptions[2]=MAX_IPOPTLEN-1;
		ipoptions[3]=4;
	}

	// fill in the probes structure
	for(i=0;i<MaxSafeTTL;i++)
	{
		tr->probes[tr->iteration][i].matched=0;
		tr->probes[tr->iteration][i].status=PROBE_STATUS_SENT;
		tr->probes[tr->iteration][i].timerID=-1;
	}
	tr->nProbes[tr->iteration] = tr->nProbesOutstanding[tr->iteration]= *nPackets;

	// leading measurement packets, ttl increasing
	for(i=0;i<maxttl;i++)
	{
		packets[i]=connection_make_packet(con);	// make a packet
		packet_get_ip_header(packets[i],&ip);
		ip.ttl=i+1;
		ip.id = make_ip_id(tr,tr->iteration,i,1);
		packet_fill_old_data(con,packets[i],1);	// IF there is outstanding data and conneciton is ESTABLISHED, these become
							// packets with 1 byte of data , else it sets the SYN|ACK or FIN|ACK 
							// flag as appropriate
		packet_set_ip_header(packets[i],&ip);   // set the ip header
		if(setRR)
			packet_set_ip_options(packets[i],ipoptions,MAX_IPOPTLEN);
		tr->probes[tr->iteration][i].ttl=i+1;
		tr->probes[tr->iteration][i].type=PROBE_MARCO;
	}
	// sanity check; used to be a problem
	for(i=0;i<(*nPackets);i++)
	{
		packet_get_ip_header(packets[i],&ip);
		assert(ip.ttl>0);
	}
	return packets;
}
