#include <assert.h>
#include <stdio.h>
#include <stdarg.h>
#include <sys/time.h>
#include <string.h>


#include "log.h"

static int SidecarLogFlags=0xffffff;
static void loginit();

char * loglevel[256];

void loginit()
{
	memset(loglevel,0,sizeof(loglevel));
	loglevel[LOGDEBUG]="DEBUG";
	loglevel[LOGINFO]="INFO";
	loglevel[LOGCRIT]="CRIT";
	loglevel[LOGDEBUG2]="DEBUG2";
	loglevel[LOGDEBUG_TS]="DEBUG_TS";
	loglevel[LOGDEBUG_RATE]="DEBUG_RATE";
	loglevel[LOGDEBUG_MPLS]="DEBUG_MPLS";
	loglevel[LOGAPP]="APP";
};



int _sidecarlog(int level ,char *file, int lineno,char * format,...)
{
	static int needInit=1;
	int count;
	va_list ap;
	struct timeval tv;

	if(needInit)
	{
		loginit();
		needInit=0;
	}
	if(!(level&SidecarLogFlags))
		return 0;	// we are surpressing these messages
	gettimeofday(&tv,NULL);
	fprintf(stderr,"%s %ld.%.6ld %s:%d-- ",loglevel[level],tv.tv_sec,(long)tv.tv_usec, file, lineno);
	va_start(ap,format);
	count = vfprintf(stderr,format,ap);
	va_end(ap);
	return count;
}


/***********************************************************************
 * int sc_setlogflags(int newflags);
 * 	return the old flags and set the new flags
 * 	this will change what is logged to the logfile
 */

int sc_setlogflags(int newflags){
	int old = SidecarLogFlags;
	SidecarLogFlags=newflags;
	return old;
}


