#ifndef LOG_H
#define LOG_H

#define LOGCRIT         0x01
#define LOGINFO         0x02
#define LOGDEBUG        0x04
#define LOGDEBUG2       0x08
#define LOGDEBUG_TS     0x10
#define LOGDEBUG_RATE   0x20
#define LOGDEBUG_MPLS   0x40
#define LOGAPP          0x80


// generic logging function
#define sidecarlog(level ,format...) _sidecarlog(level,__FILE__,__LINE__,format)
int _sidecarlog(int level ,char *file, int lineno,char * format,...);
int sc_setlogflags(int newflags);

// constants for log.c defined in sidecar.h 
#endif

