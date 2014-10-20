# sillyness to make all of the "scripts" compile

include ../Make.include


PROGS=iplane-readoutfile2src iplane-readoutfile timer

all: $(PROGS)

clean: 
	rm -f $(PROGS)

%: %.c
	$(CC) $(CFLAGS) -o $@ $+ 
%: %.cc
	$(CXX) $(CFLAGS) -o $@ $+ 
