#ifndef GRABBER_H
#define GRABBER_H

#include <pthread.h>

struct grabber_context;

#include "fast_wget.h"
#include "targets.h"

typedef struct grabber_context 
{
	int grabberID;
	struct context *ctx;
	int sock;
	pthread_t * thread;
} grabber_context;



void * grabber_thread(void * arg);

grabber_context * grabber_create(struct context *,int id);
void grabber_free(grabber_context *);

#endif
