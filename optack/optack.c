/*******************************************************************************
 * OPTACK: 	Implementation of algorithm in "Misbehaving Receivers Can Cause
 * 	Internet-Wide Congestion Collapse", but in the sidecar framework.
 *
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "sidecar.h"


typedef struct coninfo {
	u32 highestRecv;
	int timeoutID;
	int wscale
	u32 cwnd;
	int mss;
} coninfo;

/********************************************************************
 * globals
 */

int LogLevel=0;
char * PcapFilterStr = "tcp port 80";

/********************************************************************
 * protos
 */

void parse_args(int argc,char * argv[]);
void usage(char *, char *);
coninfo * coninfo_create(struct connection *);

// call backs
void optack_connCB(struct connection *);
void optack_closeCB(struct connection *);
void optack_inCB(struct connection *,struct packet *p, const struct pcap_pkthdr *phdr);
// void optack_outCB(struct connection *,struct packet *p, const struct pcap_pkthdr *phdr);


/*********************************************************************
 * main():
 * 	start sidecar
 */


int main(int argc, char * argv[])
{
	parse_args(argc, argv);
        sc_setlogflags(LogLevel);
	fprintf(stderr, "OptAcking connections that match '%s'on %s\n",PcapFilterStr,Dev);
	sc_init(PcapFilterStr,Dev,0);
	sc_register_connect(optack_connCB);     // when we get a new connection

	sc_do_loop();				// hand off control to sidecar
	return 0;
}


/**********************************************************************
 * void optack_connCB(struct connection *);
 * 	new connection callback: just print a new conn and register in call back
 */

void optack_connCB(struct connection * con)
{
	char buf[BUFLEN];
	int len=BUFLEN;
	int con_id;
	struct coninfo * ci;

	connection_get_name(con,buf,&len);
	con_id = connection_get_id(con);
	fprintf(stderr,"New connection %d :: %s\n",con_id,buf);

	ci = coninfo_create(con);		// create and store con specific data
	connection_set_app_data(con,ci);
	sc_register_in_handler(con,optack_inCB);// register callbacks
	// sc_register_out_handler(con,optack_outCB);
	sc_register_close(con,optack_closeCB);
}


/*************************************************************************
 * void optack_closeCB()
 * 	free per connection state
 */

void optack_closeCB(struct connection * con)
{
	struct coninfo *ci;
	ci = (struct coninfo *) connection_get_app_data(con);
	assert(ci);
	coninfo_free(ci);			// free data
	connection_set_app_data(con,NULL);	// just for cleanliness
}


/************************************************************************
 * void optack_inCB()
 * 	got incoming data; send lots of optimistic acks in response
 */

void optack_inCB(struct connection * con, struct packet * p, const struct pcap_pkthdr *phdr)
{
	struct tcphdr tcp;
	struct coninfo *ci;

	ci = (struct coninfo *) connection_get_app_data(con);
	assert(ci);


}
