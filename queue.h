/*
		QUEUE.H
				Rob Sherwood
				2/9/99 9:12pm
		modified in 09/01
*/

#ifndef QUEUE_H
#define QUEUE_H

#define Q_destroy Q_Destroy
#define Q_create Q_Create
#define Q_empty Q_Empty


#define REQUIRE_QUEUE_SANITY 1



typedef struct queuedata{
	void * data;
	struct queuedata * next;
} queuedata;

typedef struct queuetype {
	queuedata *start;
	queuedata *stop;
	int size;
#ifdef REQUIRE_QUEUE_SANITY
	int maxSanitySize;
#endif
} queuetype;

queuetype * Q_Create(void);
#ifdef REQUIRE_QUEUE_SANITY
queuetype * Q_Create_with_sanity_check(int maxsize);
#endif
int Q_Destroy( queuetype *);
int Q_Empty(queuetype *);
void * Pop(queuetype *);
int Q_size(queuetype *);
int Q_Enqueue(queuetype *,void *);
int Q_Push(queuetype *,void *);
void * Q_Dequeue(queuetype *);
// Elena 07Dec02
// to remove the specific element from the queue
// returns pointer to the element removed, NULL if element not found
void * Q_Remove(queuetype *, void *);

// Elena 07Dec02 testing 
void do_queue_tests();
#endif
