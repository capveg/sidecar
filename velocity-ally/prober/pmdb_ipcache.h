#ifndef PMDB_IPCACHE_H
#define PMDB_IPCACHE_H


#include "pmdb.h"

#define PMDB_IPCACHE_HASHSIZE 65536

void * pmdb_ipcache_ip2data(u_int32_t ip);
int pmdb_ipcache_hash(void *);
int pmdb_ipcache_cmp(void *, void *);

#endif
