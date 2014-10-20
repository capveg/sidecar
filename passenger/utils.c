#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "passenger.h"
#include "sidecar.h"

/******************************************************************************************
 * int make_ip_id(int iteration,int probe_num, int rpt);
 * int convert_ip_id(id,int *iteration, int *probe_num, int * rpt);
 * 	make the iteration and probe_num and rpt flag into an ip id
 * 	and convert it back
 */

int make_ip_id(struct trdata *tr ,int iteration,int probe_num,int rpt)
{
	int id;
	int err;
	probe *p;
	assert(iteration>=0);
	assert(probe_num>=0);

	id = tr->nextProbeId++;
	p = &(tr->probes[iteration][probe_num]);
	p->iteration=iteration;	// save the data
	p->probe_num=probe_num;
	p->rpt=rpt;
	err = probe_add(tr->con,id,p);
	assert(!err);
	return id;
}

int convert_ip_id(struct trdata *tr,int id, int *iteration, int *probe_num, int *rpt)
{
	probe * p;
	p = (probe *) probe_lookup(tr->con,id);
	if(p==NULL)
		return 1;		// not found
	*rpt= p->rpt;
	*iteration = p->iteration;		// everything but top bit
	*probe_num = p->probe_num;
	return 0;
}

int vnet_test()
{
	struct stat buf;
	int err;

	err = stat("/proc/sys/vnet",&buf);
	if(err==0)
		fprintf(stdout," Host appears to be running VNET: disabling FINACK probes\n");
	return(!err);
}
