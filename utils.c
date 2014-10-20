#include <netdb.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/version.h>
#include <sys/socket.h>
#include <sys/errno.h>

#include "context.h"
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


/**************************************************************************************************
 * Standard BSD internet packet checksum routine  -- snagged from nmap
 *	I should eventually figure out how to do one's complement math :-(
 *
 */

unsigned short in_cksum(u16 *ptr,int nbytes) {

	register u32 sum;
	u16 oddbyte;
	register u16 answer;

	/*
	 *         for(i=0;i<nbytes/2;i++)
	 *                         printf("%d: 0x%.4X : %u : %u\n",i,ptr[i], ptr[i], ntohs(ptr[i]));
	 *                                         */

	/*
	 *          *  * Our algorithm is simple, using a 32-bit accumulator (sum),
	 *                   *   * we add sequential 16-bit words to it, and at the end, fold back
	 *                            *    * all the carry bits from the top 16 bits into the lower 16 bits.
	 *                                     *     */

	sum = 0;
	while (nbytes > 1)  {
		sum += *ptr++;
		nbytes -= 2;
	}

	/* mop up an odd byte, if necessary */
	if (nbytes == 1) {
		oddbyte = 0;            /* make sure top half is zero */
		*((u_char *) &oddbyte) = *(u_char *)ptr;   /* one byte only */
		sum += oddbyte;
	}

	/*
	 *          *  * Add back carry outs from top 16 bits to low 16 bits.
	 *                   *   */
	while (sum>>16)
		sum = (sum & 0xffff) + (sum >> 16);
	answer = ~sum;          /* ones-complement, then truncate to 16 bits */
	return(answer);
}


/**********************************************************************************************
 * struct timeval diff_time(struct timeval now,struct timeval then);
 * 	return the difference between now and then
 * 	ASSUMES now>then; no way to return errors b/c tv is unsigned
 */

struct timeval diff_time(struct timeval now,struct timeval then)
{
	struct timeval diff;

	if(now.tv_usec<then.tv_usec)
	{
		now.tv_sec--;
		now.tv_usec+=1000000;
	}
	diff.tv_sec = now.tv_sec-then.tv_sec;
	diff.tv_usec = now.tv_usec-then.tv_usec;

	return diff;
}

/*************************************************************************************************
 * int getmemusage(long * total, long * resident)
 * 	return the mem the process is using, in bytes
 */

int getmemusage(long * total, long * resident)
{
	pid_t pid;
	int pagesize;
	FILE * statfile;
	char buf[BUFLEN];
	int err;

	pid=getpid();
	snprintf(buf,BUFLEN,"/proc/%d/statm",pid);
	statfile = fopen(buf,"r");
	if(!statfile)
	{
		perror("getmemusage::fopen:");
		return -1;
	}
	err=fscanf(statfile,"%ld %ld ",total,resident);
	if(err!=2)
		return -2;
	pagesize=getpagesize();
	*resident=(*resident)*pagesize;
	*total=(*total)*pagesize;
	fclose(statfile);
	return 0;
}

/***************************************************************************************************
 * void * _malloc_and_test(size_t size,char * file, char * linen);
 * 	called from #define malloc_and_test(x) _malloc_and_test(x,__FILE__,__LINE__)
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

/****************************************************************************************
 * float timerdiv(struct timeval * num. struct timeval * den);
 * 	return num/den, but do tricks to try to make sure the floating point math works
 */

double timerdiv(struct timeval * num, struct timeval * den)
{
	double n,d;

	n = num->tv_sec + (double)num->tv_usec/1000000;
	d = den->tv_sec + (double)den->tv_usec/1000000;
	assert(d!=0);
	return n/d;
}

/***********************************************************************************************
 * unsigned long long gethrcycle_x86()
 * 	return the number of clock ticks ellapsed from startup
 * 	(stolen from pl-users mailing list:	http://lists.planet-lab.org/pipermail/users/2004-November/000796.html)
 * 	need to multiply by CPU tick frequency to get actual time
 */

/* get the number of CPU cycles since startup */
unsigned long long gethrcycle_x86()
{
	unsigned int tmp[2];
	__asm__ ("rdtsc"

			: "=a" (tmp[1]), "=d" (tmp[0])
			: "c" (0x10) );

	return ((unsigned long long)tmp[0] << 32 | tmp[1]);
}
		
