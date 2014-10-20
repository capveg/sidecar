#ifndef MKTRAIN_H
#define MKTRAIN_H

struct packet ** make_recursive_packet_train(struct connection * con, trdata *tr,int *payload, int maxttl,int setRR, int * nPackets);

struct packet ** make_light_packet_train(struct connection * con, trdata *tr,int maxttl,int setRR, int * nPackets);

#endif
