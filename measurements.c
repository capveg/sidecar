#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "context.h"
#include "connections.h"
#include "utils.h"


/***********************************************************************************
 * int isMeasurement(struct tapcontext *ctx,struct connection * con, iphdr * ip,tcphdr * tcp);
 * 	return 1 if the given packet has been tagged by setMeasurement, 0 otherwise
 */

// FIXME: stub!
int isMeasurement(struct tapcontext *ctx,struct connection * con, iphdr * ip,tcphdr * tcp)
{
	return 0;	
}


/*********************************************************************************
 * int setMeasurement(struct tapcontext *ctx, struct connection *con, struct packet *p);
 *	flag the ident field of the outgoing packet so that we can identify it coming back
 */

// FIXME: stub!
int setMeasurement(struct tapcontext *ctx, struct connection *con, struct packet *p)
{
	return 0;
}
