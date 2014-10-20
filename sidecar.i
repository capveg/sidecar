/* sidecar.i */
%module sidecar

%{
#include "sidecar.h"
extern int Foo;
%}

%include "sidecar.h"
extern int Foo;
