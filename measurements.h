#ifndef MEASUREMENTS_H
#define MEASUREMENTS_H

#include "context.h"
#include "connections.h"
#include "packet.h"

// int measurementsLoop(tapcontext *);

int isMeasurement(struct tapcontext *ctx,struct connection * con, iphdr * ip,tcphdr * tcp);
int setMeasurement(struct tapcontext *ctx, struct connection *con, struct packet *p);


#endif
