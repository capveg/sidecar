#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/types.h>

int childPid;
char ** execList;
int timeout;
int didTimeout=0;

void catchSIGALRM(int val);
void usage(char *err);

int main(int argc, char * argv[])
{
	int status;
	int err,i;
	if(argc<3)
		usage("Need more args\n");

	execList = malloc(sizeof(char *)*argc);
	memset(execList,0,sizeof(char *)*argc);
	for(i=2;i<argc;i++)
		execList[i-2]=argv[i];
	timeout=atoi(argv[1]);
	if(timeout<=0)
	{
		usage("Bad timeout value\n");
	}
	if((childPid=fork()))
	{
		signal(SIGALRM,catchSIGALRM);
		alarm(timeout);
		waitpid(childPid,&status,0);
		if(didTimeout)	// could in theory use WIFEXITED(*status), but this clearly works
		{
			fprintf(stderr,"TIMEOUT(%d):: ",timeout);
		}
		else
		{
			fprintf(stderr,"SUCCESS(%d):: ",timeout);
		}
		i=0;
		while(execList[i]!=NULL)
			fprintf(stderr," %s",execList[i++]);
		fprintf(stderr,"\n");
		return status;
	}
	else
	{
		// child process
		err=execvp(execList[0],execList);
		perror("execvp");	// only gets here on error
		exit(1);
	}
	return 0;	// should never get here
}

void catchSIGALRM(int val)
{
	didTimeout=1;
	kill(childPid,SIGTERM);
}

void usage(char * err)
{
	if(err)
		fprintf(stderr,"%s",err);
	fprintf(stderr,"\nUsage:\n	timer <seconds> cmd [arg1 [arg2 [..]]\n");
	exit(-1);
}

