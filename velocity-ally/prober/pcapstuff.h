#ifndef PCAPSTUFF_H
#define PCAPSTUFF_H

#include <pcap.h>

pcap_t * pcap_init(char * filterStr, char * dev);

#endif
