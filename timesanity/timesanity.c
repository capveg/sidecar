#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "tsc.h"

void usage(char *s1, char *s2);

int count=1000;
long usDelay=50000;

int main(int argc, char * argv[])
{
	struct timeval delaySaved,delay;
	uint64_t startTsc,nowTsc;
	struct timeval startTv,nowTv,diffTv,diffTsc;
	int i,c;
	// FIXME need to call sched_setaffinity if we are on an SMP
	// to fix this proc to a single cpu, else we will get bogus values

	while((c=getopt(argc,argv,"c:d:"))!=-1)
	{
		switch(c)
		{
			case 'c':
				count=atoi(optarg);
				if(count<1)
					usage("Invalid arg to -c",optarg);
				break;
			case 'd':
				usDelay=atol(optarg);
				if(usDelay<1)
					usage("Invalid arg to -d",optarg);
				break;
			default:
				usage("Unknown argument: ",argv[optind]);
		}
	}
		

	tsc_delta2tv(0,0);		// this will force the file open/slow part of this 
					// function, and cache the result so that
					// it's timing is not latter affected
	delaySaved.tv_usec = usDelay%1000000;
	delaySaved.tv_sec = (usDelay-delaySaved.tv_usec)/1000000;
	startTsc=rdtsc();
	gettimeofday(&startTv,NULL);

	for(i=0;i<count;i++)
	{
		delay=delaySaved;		// b/c Linux select() will frob this value
		select(1,NULL,NULL,NULL,&delay); // sleep for delay microseconds
		nowTsc=rdtsc();
		gettimeofday(&nowTv,NULL);
		// calc diff from wall clock
		timersub(&nowTv,&startTv,&diffTv);
		// calc diff from HZ clock
		diffTsc=tsc_delta2tv(nowTsc,startTsc);
		printf("wall %ld.%.6ld	hz %ld.%.6ld\n",
				diffTv.tv_sec,diffTv.tv_usec,
				diffTsc.tv_sec,diffTsc.tv_usec);
	}

	return 0;
}



void usage(char *s1, char *s2)
{
	if(s1)
		fprintf(stderr,"%s ",s1);
	if(s2)
		fprintf(stderr,"%s ",s2);
	if(s1||s2)
		fprintf(stderr,"\n");
	fprintf(stderr,"Usage:\n"
			"timesanity [options]\n"
			"	-c count 	: number iterations [%d]\n"
			"	-d usDelay 	: delay between interations, microseconds [%ld]\n",
			count,usDelay);
	exit(1);
}
