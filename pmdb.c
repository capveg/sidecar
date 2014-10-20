#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>



#include "pmdb.h"

/*************************************************************************
 * pmdb * pmdb_create(int hashSize, int (*hash)(void *), int (*cmp)(void *,void *));
 * 	return a pointer to the poor man's data base
 */

pmdb * pmdb_create(int hashSize, int (*hash)(void *), int (*cmp)(void *,void *), int (*kfree)(void *))
{
	pmdb * db;

	db = malloc(sizeof(pmdb));
	if(db==NULL)
		return NULL;
	db->hash=hash;
	db->cmp=cmp;
	db->free=kfree;
	db->hashSize=hashSize;
	db->buckets=malloc(sizeof(pmdb_elm)*hashSize);
	if(db->buckets==NULL)
	{
		free(db);
		return NULL;
	}
	memset(db->buckets,0,sizeof(pmdb_elm)*hashSize);
	db->nEntries=0;
	return db;
}


/*****************************************************************************8
 * int pmdb_insert(pmdb * db, void * key, void * data);
 * 	insert an element into the database
 */

int pmdb_insert(pmdb * db, void * key, void * data)
{
	pmdb_elm *curr,*parent;
	int hash;
	int dir;

	hash=db->hash(key);
	assert(hash>=0);
	assert(hash<db->hashSize);
	parent=NULL;
	curr = db->buckets[hash];
	while(curr!=NULL)
	{
		dir = db->cmp(key,curr->key);
		if(dir==0)
		{
			// overwrite if this key already exists
			curr->key=key;
			curr->data=data;
			return 1;		// return >0 for success, but signal something happeend
		}
		parent=curr;
		if(dir<0)
			curr=curr->left;
		else
			curr=curr->right;
	}

	curr = malloc(sizeof(pmdb_elm));
	if(curr==NULL)
		return -2;
	curr->key=key;
	curr->data=data;
	curr->left=curr->right=NULL;
	if(parent==NULL)
		db->buckets[hash]=curr;	// first entry in this bucket
	else
	{
		if(dir<0)	// if we last went left
			parent->left=curr;
		else		// else, we went right
			parent->right=curr;
	}
	db->nEntries++;
	return 0;
}


/*********************************************************************************
 * int pmdb_exists(pmdb *db, void * key);
 * 	return 1 if key exists in db, 0 otherwise
 */


int pmdb_exists(pmdb * db, void * key)
{
	if(pmdb_lookup(db,key))
		return 1;
	else 
		return 0;
}

/*********************************************************************************
 * void * pmdb_lookup(pmdb *db, void *key);
 * 	return data if key is in db
 */


void * pmdb_lookup(pmdb * db, void * key)
{
	pmdb_elm *curr;
	int hash;
	int dir;

	hash=db->hash(key);
	assert(hash>=0);
	assert(hash<db->hashSize);
	curr = db->buckets[hash];
	while(curr!=NULL)
	{
		dir = db->cmp(key,curr->key);
		if(dir==0)	// sucess!
			return curr->data;
		if(dir<0)
			curr=curr->left;
		else
			curr=curr->right;
	}
	return NULL;		// failure
}
/**********************************************************************************
 * int pmdb_count_entries(pmdb * db);
 */
int pmdb_count_entries(pmdb * db)
{
	assert(db);
	return db->nEntries;
}


/************************************************************************************
 * int pmdb_delete(pmdb *db, void *key);
 * 	remove a key/data pair from the database
 * 	need to implement binary tree delete
 */

int pmdb_delete(pmdb *db, void *key)
{
	int NOT_IMPLEMENTED=0;
	int dir=0;
	int hash;
	pmdb_elm *curr,*prev;

	hash=db->hash(key);
	assert(hash>=0);
	assert(hash<db->hashSize);
	curr = db->buckets[hash];
	prev=NULL;
	while(curr!=NULL)	// lookup key
	{
		dir = db->cmp(key,curr->key);
		if(dir==0)	// found
			break;
		prev=curr;
		if(dir<0)
			curr=curr->left;
		else
			curr=curr->right;
	}

	if(curr==NULL)
		return -1;	// not found!
	if((curr->left==NULL)&&(curr->right==NULL))	// leaf
	{
		if(prev)
		{
			if(dir>0)	// went right last
				prev->right=NULL;
			else
				prev->left=NULL;
		}
		else
			db->buckets[hash]=NULL;		// del last entry
	}
	else if(curr->left==NULL)		// has right child
	{
		if(prev)
		{
			if(dir>0)	// went right last
				prev->right=curr->right;
			else
				prev->left=curr->right;
		}
		else
			db->buckets[hash]=curr->right;		// del head of tree
	}
	else if(curr->right==NULL)		// has right child
	{
		if(prev)
		{
			if(dir>0)	// went right last
				prev->right=curr->left;
			else
				prev->left=curr->left;
		}
		else
			db->buckets[hash]=curr->left;		// del head of tree
	}
	else
	{
		// full two child deletion case: need to implement... later
		assert(NOT_IMPLEMENTED);
	}

	if(db->free)
		db->free(curr->key);
	free(curr);

	db->nEntries--;
	return 0;
}




