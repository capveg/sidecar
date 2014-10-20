#include <netdb.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/version.h>
#include <sys/socket.h>
#include <sys/errno.h>

#include "utils.h"
#include "log.h"

/************************************************************************************************8
 * getLocalIP():
 *      return the IP of the local machine
 */

unsigned int getLocalIP(){
#ifndef NSPRING_SUCKS
  /* this is a modified version of findsrc taken from tcptraceroute 
   by Michael C. Toren, distributed under GPL.  modified by me to 
   fit my dogma about typing, and to have some pre and post conditions. */

  /* however, if someone set the device name as a parameter, sidecar should 
     maybe use ioctl(sockfd, SIOCGIFCONF, &ifc) as in stevens. */

  static in_addr_t last_address; /* in case we can reuse it when it fails */
  struct sockaddr_in sinsrc, sindest;
  int s;
  socklen_t size;
  in_addr_t dest = 0x80088008;

  if ((s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) < 0) {
    sidecarlog(LOGCRIT, "findsrc socket error: %s", strerror(errno));
    return(last_address);
  }

  memset(&sinsrc, 0, sizeof(struct sockaddr_in));
  memset(&sindest, 0, sizeof(struct sockaddr_in));

  sindest.sin_family = (sa_family_t)AF_INET;
  sindest.sin_addr.s_addr = dest;
  sindest.sin_port = htons(53); /* can be anything */

  if (connect(s, (struct sockaddr *)&sindest, sizeof(sindest)) < 0) {
    sidecarlog(LOGCRIT, "findsrc connect error, fd %d: %s", s, strerror(errno));
    close(s);
    return(last_address);
  }

  size = sizeof(sinsrc);
  if (getsockname(s, (struct sockaddr *)&sinsrc, &size) < 0) {
    sidecarlog(LOGCRIT, "findsrc getsockname error: %s", strerror(errno));
    close(s);
    return(last_address);
  }

  (void) close(s);

  if(sinsrc.sin_addr.s_addr == 0) {
    sidecarlog(LOGCRIT, " findsrc failed to find a source\n");
    return(0);
  } else if(sinsrc.sin_addr.s_addr == htonl(0x7f000001)) {
    sidecarlog(LOGCRIT, "warning: findsrc found localhost as a source, are any interfaces configured?\n");
    return(0);
  }
  
  /* store the last address, in case this procedure fails
     for a silly reason. */

  last_address = sinsrc.sin_addr.s_addr;

  // log_print(LOG_INFO, "using determined source addr 0x%x\n", sinsrc.sin_addr.s_addr);
  return sinsrc.sin_addr.s_addr;

#else
        struct hostent h, *hptr;
        char tmpbuf[BUFLEN];
        char localFQHN[BUFLEN];
        int err;
        unsigned int ret;

        assert(!gethostname(localFQHN,BUFLEN));
        gethostbyname_r(localFQHN, &h, tmpbuf, BUFLEN, &hptr, &err);
        assert(hptr != NULL);
        memcpy(&ret, hptr->h_addr, sizeof(ret));
        return ret;
#endif
}

/***************************************************************************************************
 *  void * _malloc_and_test(size_t size,char * file, char * linen);
 *       called from #define malloc_and_test(x) _malloc_and_test(x,__FILE__,__LINE__)
 */

void * _malloc_and_test(size_t size,char * file, int linen)
{
	void * ret;
	ret = malloc(size);
	if(ret)
		return ret;
	sidecarlog(LOGCRIT," malloc(%d) failed at %s:%d :: %s\n",
			size,file,linen,strerror(errno));
	assert(ret);
	return NULL;
}

