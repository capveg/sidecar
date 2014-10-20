#ifndef TARGETS_H
#define TARGETS_H

struct target;

#include "fast_wget.h"

typedef struct target
{
	char * hostname;
	int port;
	char * URL;
	char * file;
	struct target * next;
} target;

int targets_read(struct context * ctx);
void target_free(target *);
void targets_parse_html(struct context *ctx, char * buf, int len,char *sourceURL);

target * target_get_next(struct context *ctx);		// locks context
void target_randomize(struct context *ctx);
int target_add(struct context * ctx, target *); 	// locks context

int target_mark_done(struct context *, target *);

#endif
