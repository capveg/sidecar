#ifndef CALLBACKS_H
#define CALLBACKS_H


void connectCB(struct connection *);
void timewaitCB(struct connection *);
void idleCB_traceroute(struct connection *);
void idleCB_rpt(struct connection *);
void timerCB_traceroute(struct connection *,void *arg);
void timerCB_rpt(struct connection *,void *arg);
void forceCloseCB(struct connection *,void *arg);
void closeCB(struct connection *);

#endif
