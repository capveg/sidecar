#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>


#include "sidecar.h"
#include "targets.h"

static int parseURL(context * ctx,target * t,const char *line, char * filename, int linenum);



/*******************************************************************************************
 * int targets_read(struct context * ctx)
 * 	read the list of targets from the ctx->targetsFile
 * 	add then to the targets list via target_add()
 */


int targets_read(struct context * ctx)
{
	FILE * f;
	char buf[BUFLEN];
	int linecount=0;
	int err;
	int i=0;
	

	assert(ctx->targetsFile);
	f=fopen(ctx->targetsFile,"r");
	if(!f)
	{
		fprintf(stderr,"targets_read() openning '%s'::",ctx->targetsFile);
		perror("fopen");
		exit(1);
	}
	if(ctx->targets)
	{
		for(i=ctx->nTargetsDone;i<ctx->nTargets;i++)
			target_free(ctx->targets[i]);
	}
	ctx->nTargets=0;
	
	while(fgets(buf,BUFLEN,f)!=NULL)
		ctx->nTargets++;		// count number of urls
	rewind(f);				// rewind to beginning
	ctx->targets=malloc(sizeof(target*)*ctx->nTargets);
	assert(ctx->targets);
	// read through , again
	while(fgets(buf,BUFLEN,f)!=NULL)
	{
		linecount++;
		ctx->targets[i] = malloc(sizeof(target));
		assert(ctx->targets[i]);
		err=parseURL(ctx,ctx->targets[i],buf,ctx->targetsFile,linecount);
		if(err)
		{
			fprintf(stderr,"targets_read:: error parsing at %s:%d: stopping\n",ctx->targetsFile,linecount);
			exit(err);
		}
		i++;
	}
	ctx->nTargetsDone=0;
	fprintf(stdout,"targets_read:: read %d targets from %s\n",ctx->nTargets,ctx->targetsFile);
	fclose(f);
	return 0;
}

/**********************************************************************************************
 * target * target_get_next(struct context *ctx);  // locks context
 * 	grab the next target with locking
 * 	return NULL if no more targets
 * 	just push onto front (i.e., FIFO stack)
 */
target * target_get_next(context *ctx)
{
	assert(ctx);
	target *t=NULL;
	pthread_mutex_lock(ctx->targetsLock);
	if(ctx->nTargetsDone<ctx->nTargets)
		t=ctx->targets[ctx->nTargetsDone++];
	pthread_mutex_unlock(ctx->targetsLock);
	return t;
}

/***************************************************************************************************
 * void target_free(target *);
 * 	free all of the resource in a target
 */

void target_free(target *t )
{

	assert(t);
	if(t->hostname)
	{
		free(t->hostname);
		t->hostname=NULL;
	}
	if(t->URL)
	{
		free(t->URL);
		t->URL=NULL;
	}
	if(t->file)
	{
		free(t->file);
		t->file=NULL;
	}
	free(t);
}


/****************************************************************************************************
 * int parseURL(context * ctx,target * t,char *buf)
 *       "http:://host[:port]/file --> parse into target
 */   

int parseURL(context * ctx,target * t,const char *line, char * filename, int linenum)
{

	char buf[BUFLEN];
	char *token;
	char *port,*file;
	char * ptr;
	assert(t);
	assert(ctx);
	ptr=NULL;
	// make a local copy
	strncpy(buf,line,MIN(strlen(line),BUFLEN-1));
	token= strtok_r(buf,"/",&ptr); // non-reentrant version would kill us; use _r
	if(!token || strcmp(token,"http:"))
	{
		fprintf(stderr,"parseURL:: url must start with http://.../, got: %s",token);
		return 1;
	}
	token = strtok_r(NULL,"/",&ptr);
	if((!token) || (!strcmp(token,"")))
	{
		fprintf(stderr,"Malformed url at pass 2: %s :: %s:%d\n",token,filename,linenum);
		return 2;
	}
	file = strtok_r(NULL," \t\n\r",&ptr);
	if((!file) || (!strcmp(file,"")))
	{
		fprintf(stderr,"Malformed url at pass 3: %s :: %s:%d\n",token,filename,linenum);
		return 3;
	}
	port = index(token,':');		// token = "hostname:port"
	if(port){
		*port = 0;			// strip off the port from the hostname
		port++;
		t->port = atoi(port);
	} else {
		t->port = 80;
	}
	t->hostname=strdup(token);
	t->URL=strdup(line);
	ptr=index(t->URL,'\n');
	if(ptr!=NULL)
		*ptr=0;			// chomp()
	t->file=strdup(file);
	return 0;
}


/***********************************************************************************************************
 * void target_randomize(struc context *ctx);
 * 	randomize the order the targets are visited
 */

void target_randomize(struct context *ctx)
{
	int i,j;
	target *tmp;
	srand(time(NULL)+getpid());
	for(i=0;i<ctx->nTargets;i++)
	{
		j = rand()% (ctx->nTargets - i );
		tmp = ctx->targets[j];
		ctx->targets[j]=ctx->targets[i];
		ctx->targets[i]=tmp;
	}
}

