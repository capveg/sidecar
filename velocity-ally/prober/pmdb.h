/***************************************************************
 * PMDB: poor man's database
 * 	create an array of hash buckets where each hash bucket is a
 * 	binary search tree
 */

#ifndef PMDB_H
#define PMDB_H

typedef struct pmdb_elm
{
	void * key;
	void * data;
	struct pmdb_elm *left, *right;
} pmdb_elm;


typedef struct pmdb
{
	int (*hash)(void *);
	int (*cmp)(void *,void *);
	int (*free)(void *);
	pmdb_elm ** buckets;
	int hashSize;
	int nEntries;
} pmdb;

pmdb * pmdb_create(int hashSize, int (*hash)(void *), int (*cmp)(void *,void *),int (*kfree)(void *));
int pmdb_insert(pmdb * db, void * key, void * data);
int pmdb_exists(pmdb *db, void * key);
void * pmdb_lookup(pmdb *db, void *key);
int pmdb_count_entries(pmdb *);


int pmdb_delete(pmdb *db, void *key);	// not implemented!

#endif
