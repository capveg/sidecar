#ifndef PROBE_SCHEDULE_H
#define PROBE_SCHEDULE_H

#include "passenger.h"

/******
 * this function will change the phase, and set nextTTL to the correct next probe
 * 	it will also set tr->done==1 if no more probes should be sent
 *
 * 	parameters:
 * 	set endhost==1 if the last probe hit an endhost
 * 	set nat_or_firewall if the last probe was a nat or firewall
 */

void calc_next_probe(struct connection *con , struct trdata *tr, int endhost,int nat_or_firewall);

#endif
