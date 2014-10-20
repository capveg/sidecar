// set of functions to put into pmdb.c
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "pmdb_ipcache.h"


void * pmdb_ipcache_ip2data(u_int32_t ip)
{
	void * ret = malloc(sizeof(ip));
	assert(ret!=NULL);
	memcpy(ret,&ip,sizeof(ip));
	return ret;
}

int pmdb_ipcache_hash(void * key)
{
	int hash;
	u_int32_t * ip = (u_int32_t*) key;
	
	// fold the first two bytes onto the second 2 bytes
	hash = ((*ip&0xff00)>>16)^(*ip&0x00ff);
	return hash;
}


int pmdb_ipcache_cmp(void *a, void *b)
{
	u_int32_t ip1, ip2;
	ip1=*(u_int32_t*)a;
	ip2=*(u_int32_t*)b;
	if(ip1==ip2)
		return 0;
	return (ip1>ip2)?-1:1;
}

