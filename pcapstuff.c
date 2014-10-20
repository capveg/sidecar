#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include "context.h"
#include "connections.h"
#include "log.h"

/***************************************************************************************************
 * pcap_init()
 *      open pcap on the specified interface, set the filter, and store the handle in the ctx
 */

int pcap_init(tapcontext * ctx)
{
        char errbuf[PCAP_ERRBUF_SIZE];
        char * dev;
        bpf_u_int32 mask=0, net=0;
        struct bpf_program filter;
        char filterstr[BUFLEN];
        char tmpbuf[BUFLEN];


        dev = ctx->dev;
        memset(errbuf,0,PCAP_ERRBUF_SIZE);	// trying to shutup valgrind
        memset(filterstr,0,BUFLEN);
        memset(tmpbuf,0,BUFLEN);
        memset(&filter,0,sizeof(struct bpf_program));

        if(dev == NULL) {
          /* we haven't been told what device to use */
                dev = pcap_lookupdev(errbuf);
                if(!dev){
                  sidecarlog(LOGCRIT,"ER: pcap_lookupdev: %s\n",errbuf);
                  return(1);
                } else {
                  ctx->dev=strdup(dev);
                }
        }

        if(pcap_lookupnet(dev,&net,&mask,errbuf) == -1){
                sidecarlog(LOGCRIT,"ER: pcap_lookupnet: %s; ",errbuf);
                return(1);
        }
        sidecarlog(LOGDEBUG,"Listening on Device: %s\n", dev);

        ctx->handle = pcap_open_live(dev, MYSNAPLEN, 0, 0, errbuf);
        if(!ctx->handle){
                sidecarlog(LOGCRIT,"ER: pcap_open_live: %s\n",errbuf);
                return(3);
        }

       // use PCap's filtering...but we will do most of it by hand in the packetGrabber
       inet_ntop(AF_INET,&ctx->localIP,tmpbuf,BUFLEN);
       snprintf(filterstr,BUFLEN,"host %s and (icmp or ( %s ) ) ", tmpbuf, ctx->pcapfilter);
       sidecarlog(LOGINFO,"Filtering on : '%s'\n",filterstr);
	if(pcap_compile(ctx->handle,&filter,filterstr,1,net)==-1){
		sidecarlog(LOGCRIT,"ER: pcap_compile: %s\n",errbuf);
		return(4);
	}

	if(pcap_setfilter(ctx->handle,&filter ) == -1){
		sidecarlog(LOGCRIT,"ER: pcap_setfilter: %s\n",errbuf);
		return (5);
	}

	assert(pcap_datalink(ctx->handle)==DLT_EN10MB);      // currently don't handle non-ethernet people
	if(pcap_setnonblock(ctx->handle, 1, errbuf))
	{
		sidecarlog(LOGCRIT,"ER: pcap_setnonblock(): %s\n",errbuf);
		return(6);
	}
	return 0 ;
}
