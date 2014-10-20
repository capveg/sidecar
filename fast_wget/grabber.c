#include <assert.h>
#include <errno.h>
#include <netdb.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/types.h>
#include <errno.h>

#include <netinet/in.h>

#include "grabber.h"
#include "utils.h"



void * resolve_thread(void * arg);

/*****************************************************************************
 * grabber_context * grabber_create(int id);
 * 	malloc a grabber_context,
 * 	fill it in,
 * 	spawn a grabber_thread pthead_d
 * 	return the grabber_context
 */

grabber_context * grabber_create(context * ctx,int id)
{
	grabber_context * gctx;

	gctx= malloc(sizeof(grabber_context));
	assert(gctx);
	memset(gctx,0,sizeof(grabber_context));
	gctx->grabberID=id;
	gctx->sock=-1;
	
	// init rest of structure
	gctx->ctx=ctx;
	// create and spawn the thread
	gctx->thread = malloc(sizeof(pthread_t ));
	assert(gctx->thread);
	memset(gctx->thread,0,sizeof(pthread_t));
	switch(ctx->mode)
	{
		case MODE_GRAB:
			pthread_create(gctx->thread,NULL,grabber_thread,gctx);
			break;
		case MODE_RESOLV:
			pthread_create(gctx->thread,NULL,resolve_thread,gctx);
			break;
		default:
			fprintf(stderr,"Unknown mode %d\n",ctx->mode);
			break;
	}
	
	// return structure
	return gctx;
}
/******************************************************************
 * void grabber_free(grabber_ctx * gtx)
 */

void grabber_free(grabber_context * gctx)
{
	free(gctx->thread);
	free(gctx);
}

/**************************************************************************
 * void * grabber_thread(void * arg);
 * 	while (target = getnext target)
 * 	{
 * 		GET URL from target
 * 		wait for flag
 * 		close connection
 * 	}
 */

void * grabber_thread(void * arg)
{
	int err;
	target * t;
	char buf[BUFLEN+1];
	grabber_context * gctx = (grabber_context *)arg;
	context * ctx = gctx->ctx;
	int content_len;
	int content_html;
	long randDelay;
	int status;
	struct timespec ts;
	struct timeval starttime,endtime,waittime,tmptime;
	time_t timep;

	// delay a random time in [0:ctx->mswaitTime] miliseconds to avoid syncronized writes
	randDelay = rand()%ctx->mswaitTime;
	ts.tv_sec=randDelay/1000;
	ts.tv_nsec = (randDelay%1000)*1000000;		// rand() state SHOULD be shared across threads
	printf("Thread %d sleeping for %ld.%.9ld seconds\n",gctx->grabberID,ts.tv_sec, ts.tv_nsec);
	nanosleep(&ts,NULL);
	while((t = target_get_next(ctx))!=NULL)
	{
		gettimeofday(&starttime,NULL);				
		gctx->sock = make_tcp_connection(t->hostname,t->port,ctx->connectTimeout);
		if(gctx->sock<=0)
		{
			strerror_r(errno,buf,BUFLEN);
			fprintf(stdout,"Got %d (%s) connecting to %s:%d; skipping\n",
					gctx->sock,buf,t->hostname,t->port);
			ctx->errCount++;
			target_free(t);
			continue;
		} 

		switch(ctx->protocol)
		{
		    case PROTO_WWW:
			snprintf(buf,BUFLEN,
					"HEAD /%s HTTP/1.1\r\n"
					"Host: %s\r\n"
					"User-Agent: Mozilla/5.0 (Compat: Internet CoreMapping Project http://www.cs.umd.edu/~capveg/sidecar for details; capveg@cs.umd.edu for concerns)\r\n"
					"Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5\r\n"
					"Accept-Language: en-us,en;q=0.5\r\n"
					"Accept-Encoding: gzip,deflate\r\n"
					"Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7\r\n"
					"Keep-Alive: 300\r\n"
					"Connection: keep-alive\r\n"
					"\r\n",
					t->file,
					t->hostname);
			break;
		    case PROTO_BT:
			snprintf(buf,BUFLEN,"%cBitTorrent protocol",19);
			break;
		    default:
			fprintf(stderr,"Unknown protocol type %d\n",ctx->protocol);
			abort();
		}
	
		err=timeout_writeall(&status,gctx->sock,buf,strlen(buf),ctx->writeTimeout);
		if(err || status<=0)
		{
			fprintf(stdout,"grabber_thread :: error writing for URL %s : err=%d status=%d\n",
					t->URL,err,status);
			shutdown(gctx->sock,SHUT_WR);
			close(gctx->sock);
			target_free(t);
			continue;
		}
		content_len=-1;
		content_html=0;
		do	// read what the client has to tell us, and just ignore it
		{
			err = timeout_read(&status,gctx->sock,buf,BUFLEN,ctx->mswaitTime);
		} while((err==0)&&(status>0));			// until we timeout or they close the connection

		gettimeofday(&endtime,NULL);
		timersub(&endtime,&starttime,&tmptime);			// calc the time between start and stop
		endtime=tmptime;
		waittime.tv_sec= ctx->mswaitTime/1000;		// calc time left to wait
		waittime.tv_usec= ctx->mswaitTime%1000;
		timersub(&waittime,&endtime,&tmptime);			
		waittime=tmptime;
		tmptime.tv_sec=tmptime.tv_usec=0;
		if(timercmp(&waittime,&tmptime,>))			// if we need to wait longer
		{
			ts.tv_sec = waittime.tv_sec;			// convert to timespec
			ts.tv_nsec = 1000*waittime.tv_usec;
			nanosleep(&ts,NULL);				// sleep for the remaining time before shutdown
		}
		shutdown(gctx->sock,SHUT_WR);
		close(gctx->sock);	
		timep=time(NULL);
		// printf("URL %40s done at %30s",t->URL,asctime_r(localtime_r(&timep,&tmptr),buf));
		if(ctx->verbose)
			fprintf(stdout,"Done: %s:%d\n",t->hostname,t->port);
		target_free(t);
	}
	pthread_cond_signal(&ctx->isDoneCond);		// signal that this thread is done
	return NULL;
}



/******************************************************************8
* void * resolver_thread(void *)
*	just do DNS resolution on the address and print it
*/

void * resolve_thread(void * arg)
{
	grabber_context * gctx = (grabber_context *)arg;
	context * ctx = gctx->ctx;
	struct addrinfo hints, *result, *curr;
	struct sockaddr_in *sa_in;
	target *t;
	int err;
	char buf[BUFLEN];

	memset(&hints,0,sizeof(struct addrinfo));
	hints.ai_family= AF_INET;
	hints.ai_socktype= SOCK_STREAM;
	hints.ai_protocol= IPPROTO_TCP;

	while((t = target_get_next(ctx))!=NULL)
	{
		err = getaddrinfo(t->hostname,NULL,NULL,&result);
		if(err == EAI_NONAME)	// not found
		{
			target_free(t);
			continue;
		}
		if(err)
		{
			fprintf(stderr,"Lookup for %s returned %d :: %s\n",
					t->hostname, err, gai_strerror(err));
			target_free(t);
			continue;
		}

		sa_in  =  (struct sockaddr_in*) result->ai_addr; 
		inet_ntop(AF_INET,&sa_in->sin_addr,buf,BUFLEN);
		printf("A: %s %s\n",t->hostname,buf);
		curr= result->ai_next;
		while(curr)
		{
			sa_in  =  (struct sockaddr_in*) curr->ai_addr; 
			inet_ntop(AF_INET,&sa_in->sin_addr,buf,BUFLEN);
			printf("X: %s %s\n",t->hostname,buf);
			curr= curr->ai_next;
		}
		freeaddrinfo(result);
		target_free(t);
	}
	return NULL;
}
