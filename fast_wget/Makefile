TARGET=fast_wget
include ../Make.include
CFLAGS+=-Wall -I/usr/include/pcap
CFLAGS+=-I..


SRC=$(wildcard $(VPATH)/*.c)
HDRS=$(wildcard include/*.h)
OBJS=$(subst $(VPATH)/,,$(subst .c,.o,$(SRC)))
LIBS+=-lpthread 



all: .depend tags $(TARGET)

ifeq (.depend,$(wildcard .depend))
include .depend
endif


$(TARGET): $(OBJS) 
	$(CC) $(LDFLAGS) -o $(TARGET) $(OBJS) $(LIBS) 


%.o: %.c
	$(CC) $(CFLAGS) -c $<
%.o: %.cxx
	$(CXX) $(CFLAGS) -c $<

clean: 
	@rm -f $(OBJS) core core.* $(TARGET) .depend tags
sclean: clean 
	@rm -rf outdir-*
crap: sclean cvs all

install: all
	mkdir -p $(PREFIX)
	cp $(TARGET) urls.good urls.plab $(PREFIX)/

install_clean:
	rm -f $(PREFIX)/$(TARGET)
	@rmdir --ignore-fail-on-non-empty $(PREFIX)

	

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
