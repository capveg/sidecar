TARGET=timesanity
include ../Make.include
CFLAGS+=-I..

SRC=$(wildcard $(VPATH)/*.c)
HDRS=$(wildcard include/*.h)
OBJS=$(subst $(VPATH)/,,$(subst .c,.o,$(SRC)))
#LIBS+=-lpthread 
LIBS+=-lm
#LIBS+=-lsidecar
LIBS+=../libsidecar.a
LDFLAGS+=-Wl,-rpath=.. -Wl,-rpath=. -L..



all:  .depend tags $(TARGET)

ifeq (.depend,$(wildcard .depend))
include .depend
endif


$(TARGET): $(OBJS) ../libsidecar.a
	$(CC) $(LDFLAGS) -o $(TARGET) $(OBJS:unittest.o=) $(LIBS) 


%.o: %.c
	$(CC) $(CFLAGS) -c $<
%.o: %.cxx
	$(CXX) $(CFLAGS) -c $<

install: all
	mkdir -p $(PREFIX)
	cp $(TARGET) $(PREFIX)/$(TARGET)
	chmod 755 $(PREFIX)/$(TARGET)
install_clean:
	rm -f $(PREFIX)/$(TARGET)
	@rmdir --ignore-fail-on-non-empty $(PREFIX)

test: unittest
	./unittest

unittest: $(OBJS)
	$(CC) $(LDFLAGS) -o unittest unittest.o utils.o $(LIBS) 


clean: 
	@rm -f $(OBJS) core core.* $(TARGET) .depend tags unittest
sclean: clean 
	@rm -rf outdir-*
crap: sclean cvs all
	

count:
	@wc -l $(SRC) $(HDRS) Makefile 

.depend: $(SRC) $(HDRS)
	@$(CC) -M $(CFLAGS) $(SRC)  > .depend

tags: $(SRC) $(HDRS)
	@$(CTAGS) $(SRC) $(HDRS)

cvs: 
	cvs update

debug: 
	@echo OBJ=$(OBJS)
	@echo SRC=$(SRC)
