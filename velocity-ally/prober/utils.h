#ifndef UTILS_H
#define UTILS_H

#ifndef MIN
#define MIN(x,y) ((x)>(y)?(y):(x))
#endif
#ifndef MAX
#define MAX(x,y) ((x)>(y)?(x):(y))
#endif

#include <sys/types.h>

#define malloc_and_test(x) _malloc_and_test(x,__FILE__,__LINE__)

/* important that this be uint32_t; u32 doesn't seem to have the desired
   effect on nspring's 64-bit box. */
typedef struct pseudohdr {
	/*for computing TCP checksum, see TCP/IP Illustrated p. 145 */
	u_int32_t s_addr;
	u_int32_t d_addr;
	u_int8_t zero;
	u_int8_t proto;
	u_int16_t length;
} pseudohdr;

unsigned int getLocalIP();
void * _malloc_and_test(size_t size,char * file, int linen);
/* 
 * unsigned short in_cksum(u16 *ptr,int nbytes);
struct timeval diff_time(struct timeval now,struct timeval then);
int getmemusage(long * total, long * resident);
double timerdiv(struct timeval * num, struct timeval * den);
unsigned long long gethrcycle_x86();
*/


#endif
