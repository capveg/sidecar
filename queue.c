/*
			QUEUE.C
					Rob Sherwood
					2/9/99 9:16pm
*/


#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "queue.h"
#include "utils.h"


/***********/
queuetype *Q_Create(){
	queuetype *p;

	if((p=malloc_and_test(sizeof(queuetype))) ==NULL){
		return NULL;
		}
	p->start=NULL;
	p->stop=NULL;
#ifdef REQUIRE_QUEUE_SANITY
	p->maxSanitySize=-1;
#endif
	p->size=0;

	return p;
}

/***********************************************8
 * queuetype * Q_Create_with_sanity_check(int maxsize);
 * 	create a queue with a max size sanity check
 */

#ifdef REQUIRE_QUEUE_SANITY
queuetype *Q_Create_with_sanity_check(int maxsize){
	queuetype *p;

	if((p=malloc_and_test(sizeof(queuetype))) ==NULL){
		return NULL;
		}
	p->start=NULL;
	p->stop=NULL;
	p->maxSanitySize=maxsize;
	p->size=0;
	return p;
}
#endif


/************/
int Q_size(queuetype *p){
	assert(p);
	return p->size;
}

/***********/
int Q_Destroy(queuetype *queue){
	queuedata *p,*q;

	if(queue ==NULL)  return -1;

	q=queue->start;

	while(q !=NULL){
		p=q;
		q=q->next;
		free(p);
	}

	free(queue);
	return 0;
}
/***********/
int Q_Empty(queuetype *q){

	if(q==NULL) {
		return -1;
	}
	return ( q->start == NULL)? 1: 0;

}
/*********** adds to end of queue */
int Q_Enqueue(queuetype *q,void * datum){
	queuedata *neo_datum;	

	if((neo_datum = malloc_and_test(sizeof(queuedata))) == NULL){
		return -1;
	}
	neo_datum->data=datum;
	neo_datum->next=NULL;
	if(q->start == NULL){
		assert(q->stop==NULL);
		q->start=neo_datum;
		q->stop=neo_datum;
	} else {
		assert(q->stop);
		q->stop->next=neo_datum;
		q->stop=neo_datum;
	}
	q->size++;
#ifdef REQUIRE_QUEUE_SANITY
	assert(q->maxSanitySize==-1 || q->size<q->maxSanitySize);
#endif
	return 0;
}
/********** removes from front of queue */
void * Q_Dequeue(queuetype *queue){
	queuedata *q;
	void * datum;

	if( queue ==NULL || queue->start ==NULL)
		return ( void * )NULL;

	q=queue->start;
	datum=q->data;
	queue->start=q->next;
	if(queue->start==NULL)
		queue->stop=NULL;
	free(q); 

	queue->size--;
#ifdef REQUIRE_QUEUE_SANITY
	assert(queue->size>=0);
#endif
	return datum;
}
/**** adds to front of queue **/
int Q_Push(queuetype *q,void * datum){
	queuedata *neo_datum;	

	if((neo_datum = malloc_and_test(sizeof(queuedata))) == NULL){
		return -1;
	}
	neo_datum->data=datum;
	neo_datum->next=q->start;
	if(!q->start)
		q->stop=neo_datum;
	q->start=neo_datum;
	q->size++;
#ifdef REQUIRE_QUEUE_SANITY
	assert(q->maxSanitySize==-1 || q->size<q->maxSanitySize);
#endif
	return 0;
}

// Elena 07Dec02
void * Q_Remove(queuetype *theQP, void * theElmtP) {
  queuedata *d, *prev;
  void * rv = NULL;

  assert(theQP);

  prev = NULL;
  d = theQP->start;
  while (d != NULL) {
    if (d->data == theElmtP) {
      rv = theElmtP;
      // remove the element from the queue
      if (prev == NULL) {
      // element at head
	theQP->start = d->next;
      }
      else if (d == theQP->stop) {
	// element at tail
	theQP->stop = prev;
	theQP->stop->next = NULL;
      }
      else {
      // element in the middle
	prev->next = d->next;
      }
      // deallocate queue element
      free(d);
      break;
    }
    else {
      prev = d;
      d = d->next;
    }
  }

  return rv;
}

void do_queue_tests() {
  queuetype *qP = Q_Create();
  int elmts[6] = {0,1,2,3,4,5};
  int i;
  int *elmtP;

  for(i = 0; i < 6; ++i) {
    Q_Enqueue(qP, &elmts[i]);
  }

  // remove from beginning
  elmtP = (int *)Q_Remove(qP, &elmts[0]);
  assert(elmtP!=NULL);
  assert(*elmtP == 0);
  assert(Q_size(qP) == 5);

  // remove from end
  elmtP = (int *)Q_Remove(qP, &elmts[5]);
  assert(elmtP!=NULL);
  assert(*elmtP == 5);
  assert(Q_size(qP) == 4);

  // remove from middle
  elmtP = (int *)Q_Remove(qP, &elmts[3]);
  assert(elmtP!=NULL);
  assert(*elmtP == 3);
  assert(Q_size(qP) == 3);

  // dequeue
  elmtP = (int *)Q_Dequeue(qP);
  assert(elmtP != NULL);
  assert(*elmtP == 1);
  assert(Q_size(qP) == 2);

  // destroy
  Q_Destroy(qP);
}


