// set of functions to put into pmdb.c
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "pmdb_echoidcache.h"


void * pmdb_echoidcache_echo2data(u16 echoid)
{
	void * ret = malloc(sizeof(echoid));
	assert(ret!=NULL);
	memcpy(ret,&echoid,sizeof(echoid));
	return ret;
}

int pmdb_echoidcache_hash(void * key)
{
	u16 * echoid = (u16*) key;
	
	return *echoid;		// identity hash
}


int pmdb_echoidcache_cmp(void *a, void *b)
{
	u16 echoid1,  echoid2;
	echoid1=*(u16*)a;
	echoid2=*(u16*)b;
	if(echoid1==echoid2)
		return 0;
	return (echoid1>echoid2)?-1:1;
}


int pmdb_echoidcache_free(void *key)
{
	free(key);
	return 0;
}

