#ifndef UTILS_H
#define UTILS_H

struct trdata ;
#include "sidecar.h"

int make_ip_id(struct trdata *,int iteration,int probe_num, int rpt);
int convert_ip_id(struct trdata *,int id,int *iteration, int *probe_num, int *rpt);
int unittest_ip_maps();

#endif

