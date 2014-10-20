#ifndef PACKET_HANDLERS_H
#define PACKET_HANDLERS_H

void icmpCB(struct connection *,struct packet *,const struct pcap_pkthdr* );
void inCB(struct connection *,struct packet *,const struct pcap_pkthdr* );
void outCB(struct connection *,struct packet *,const struct pcap_pkthdr* );



#endif
