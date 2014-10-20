// set of functions to put into pmdb.c
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "pmdb_ipcache.h"


void * pmdb_ipcache_ip2data(u32 ip)
{
	void * ret = malloc(sizeof(ip));
	assert(ret!=NULL);
	memcpy(ret,&ip,sizeof(ip));
	return ret;
}

int pmdb_ipcache_hash(void * key)
{
	int hash;
	u32 * ip = (u32*) key;
	
	// fold the first two bytes onto the second 2 bytes
	hash = ((*ip&0xff00)>>16)^(*ip&0x00ff);
	return hash;
}


int pmdb_ipcache_cmp(void *a, void *b)
{
	u32 ip1, ip2;
	ip1=*(u32*)a;
	ip2=*(u32*)b;
	if(ip1==ip2)
		return 0;
	return (ip1>ip2)?-1:1;
}

