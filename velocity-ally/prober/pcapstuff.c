#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <pcap.h>
#include "log.h"

/***************************************************************************************************
 * pcap_init()
 *      open pcap on the specified interface, set the filter, and store the handle in the ctx
 */

#ifndef BUFLEN
#define BUFLEN 4096
#endif

#ifndef MYSNAPLEN
#define MYSNAPLEN 1500
#endif

pcap_t *  pcap_init(char * filterStr, char * dev)
{
        char errbuf[PCAP_ERRBUF_SIZE];
        bpf_u_int32 mask=0, net=0;
        struct bpf_program filter;
        char tmpbuf[BUFLEN];
	pcap_t * handle;


        memset(errbuf,0,PCAP_ERRBUF_SIZE);	// trying to shutup valgrind
        memset(tmpbuf,0,BUFLEN);
        memset(&filter,0,sizeof(struct bpf_program));

        if(dev == NULL) {
          /* we haven't been told what device to use */
                dev = pcap_lookupdev(errbuf);
                if(!dev){
                  sidecarlog(LOGCRIT,"ER: pcap_lookupdev: %s\n",errbuf);
                  return NULL;
                } 
        }

        if(pcap_lookupnet(dev,&net,&mask,errbuf) == -1){
                sidecarlog(LOGCRIT,"ER: pcap_lookupnet: %s; ",errbuf);
                return NULL;
        }
        sidecarlog(LOGDEBUG,"Listening on Device: %s\n", dev);

        handle = pcap_open_live(dev, MYSNAPLEN, 0, 0, errbuf);
        if(!handle){
                sidecarlog(LOGCRIT,"ER: pcap_open_live: %s\n",errbuf);
                return NULL;
        }

       // use PCap's filtering...but we will do most of it by hand in the packetGrabber
       sidecarlog(LOGINFO,"Filtering on : '%s'\n",filterStr);
	if(pcap_compile(handle,&filter,filterStr,1,net)==-1){
		sidecarlog(LOGCRIT,"ER: pcap_compile: %s\n",errbuf);
		return NULL;
	}

	if(pcap_setfilter(handle,&filter ) == -1){
		sidecarlog(LOGCRIT,"ER: pcap_setfilter: %s\n",errbuf);
		return  NULL;
	}

	assert(pcap_datalink(handle)==DLT_EN10MB);      // currently don't handle non-ethernet people
	if(pcap_setnonblock(handle, 1, errbuf))
	{
		sidecarlog(LOGCRIT,"ER: pcap_setnonblock(): %s\n",errbuf);
		return NULL;
	}
	return handle ;
}
