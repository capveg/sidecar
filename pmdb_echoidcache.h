#ifndef PMDB_ECHOCACHE_H
#define PMDB_ECHOCACHE_H

#include "sidecar.h"
#include "pmdb.h"

#define PMDB_ECHOIDCACHE_HASHSIZE 65536

void * pmdb_echoidcache_echo2data(u16 echoid);
int pmdb_echoidcache_hash(void *);
int pmdb_echoidcache_cmp(void *, void *);
int pmdb_echoidcache_free(void *);

#endif
