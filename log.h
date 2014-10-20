#ifndef LOG_H
#define LOG_H

#include "sidecar.h"

// generic logging function
// from sidecar.h :: #define sidecarlog(level ,format...) _sidecarlog(level,__FILE__,__LINE__,format)
// int _sidecarlog(int level ,char *file, int lineno,char * format,...);
int sc_setlogflags(int newflags);

// constants for log.c defined in sidecar.h 
#endif

