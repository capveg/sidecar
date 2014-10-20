#ifndef TSC_H
#define TSC_H

#include <time.h>
#include <stdint.h>


struct timeval tsc_delta2tv(uint64_t then, uint64_t now);
uint64_t rdtsc();


#endif
