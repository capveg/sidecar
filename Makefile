TARGET=libsidecar
PREFIX=$(shell pwd)/tar

############
include Make.include
CFLAGS+=-I/usr/include/pcap

SWIG=sidecar
SWIGOBJ=$(SWIG)_wrap.o
SWIGSRC=$(SWIG)_wrap.cxx
#SWIGCFLAGS=-D_GNU_SOURCE -I/usr/lib/perl5/5.8.5/i386-linux-thread-multi/CORE

SRC=$(wildcard $(VPATH)/*.c) 
SRC+=$(wildcard $(VPATH)/*.cxx)
HDRS=$(wildcard include/*.h)
OBJS=$(subst $(VPATH)/,,$(subst .c,.o,$(SRC)))
LIBS+=-lm
#LIBS+=-lpthread 
LIBS+=-lpcap

# our local build isn't binary compatible with plab :-( :-( even though we're just running FC6
#SRINTERPRETER=$(shell which srinterpreter)
SRINTERPRETER=scripts/srinterpreter.plab-bin


SUBDIRS=passenger fast_wget sideping sidetrace artrat smtpnoop timesanity
PAPERS=paper worlds06.paper

.PHONY: subdirs subdirsclean papers

all: version.h .depend tags $(TARGET).so $(TARGET).a subdirs

papers:
	@for dir in $(PAPERS); do make -C $$dir; done

ifeq (.depend,$(wildcard .depend))
include .depend
endif

# grab and make scriptroute
scriptroute: 
	cd .. && \
	mkdir scriptroute && \
	cd scriptroute && \
	svn co https://subversion.umiacs.umd.edu/scriptroute/scriptroute/trunk/. . && \
	sh autogen.sh && \
	make
# grab and make undns
undns: 
	cd .. && \
	mkdir undns && \
	cd undns && \
	svn co https://subversion.umiacs.umd.edu/undns/trunk/. . && \
	sh FromCVS.sh && \
	make
	


$(TARGET).so: $(OBJS)  
	$(CC) -shared $(LDFLAGS) -o $(TARGET).so $(OBJS:unittest.o=) $(LIBS)
$(TARGET).a: $(OBJS)  
	$(AR) r $(TARGET).a $(OBJS:unittest.o=)
	$(RANLIB) $(TARGET).a

# $(TARGET): $(OBJS)  $(SWIGOBJ)
# 	$(CXX) -shared $(LDFLAGS) -o $(TARGET).so $(OBJS) $(LIBS) $(SWIGOBJ)
# 
# $(SWIGSRC): $(SWIG).i $(TARGET).h
# 	swig -perl5 -c++ $(SWIG).i
# 
# $(SWIGOBJ): $(SWIGSRC) 
# 	$(CXX) $(SWIGCFLAGS) -fPIC $(CFLAGS) -c $(SWIGSRC)
# 
subdirs:
	@for dir in $(SUBDIRS) ; do make -C $$dir ; done
subdirsclean:
	@for dir in $(SUBDIRS) ; do make -C $$dir clean ; done

unittest: $(OBJS) unittest.o
	$(CC) $(LDFLAGS) -o unittest $(OBJS) $(LIBS)

tar: sidecar.tgz
sidecar.tgz: install
	$(GTAR) cvzf sidecar.tgz -C tar .
install: all
	mkdir -p $(PREFIX)
	cp $(TARGET).so $(PREFIX)/$(TARGET).so
	cp scripts/alertmail*.py scripts/run.sh scripts/gdb-passenger-run  scripts/run-gdb.sh $(PREFIX)
	cp scripts/gtar_daemon.pl scripts/run-val.sh $(PREFIX)
	cp scripts/codeen_sidecar.run.sh $(PREFIX)
	#cp scripts/run-smtpnoop.sh $(PREFIX)
	cp scripts/randomize $(PREFIX)
	cp scripts/run-rand.sh $(PREFIX)
	cp scripts/cvtimeout.rb $(PREFIX)
	cp random_prober/informed_probe.sru random_prober/*.rb $(PREFIX)
	cp random_prober/HOSTS.ip.stoplist $(PREFIX)
	cp random_prober/stoplist.22.gz $(PREFIX)
	cp `ldd ./passenger/passenger | grep libpcap | awk '{print $$3}'` $(PREFIX)
	ldd ./passenger/passenger | grep -q efence && cp `ldd ./passenger/passenger | grep efence | awk '{print $$3}'` $(PREFIX) || true
	cp -p tar_install/* $(PREFIX)/
	@for dir in $(SUBDIRS) ; do make -C $$dir install "PREFIX=$(PREFIX)"; done

install_clean:
	rm -f sidecar.tgz
	rm -f $(PREFIX)/$(TARGET).so
	rmdir --ignore-fail-on-non-empty $(PREFIX)
	@for dir in $(SUBDIRS) ; do make -C $$dir install_clean "PREFIX=$(PREFIX)"; done


%.o: %.c
	$(CC) -fPIC $(CFLAGS) -c $<
%.o: %.cxx
	$(CXX) -fPIC $(CFLAGS) -c $<

clean: subdirsclean 
	@rm -f $(OBJS) core core.* $(TARGET) $(TARGET).so .depend tags $(SWIGOBJ) sidecar.pm $(SWIGSRC) unittest version.h sidecar.tgz $(TARGET).a
sclean: clean 
	@rm -rf outdir-*
crap: sclean cvs all

count:
	@wc -l `find $(SUBDIRS) -name \*.c -o -name \*.h -o -name Makefile`| sort -n

.depend: $(SRC) $(HDRS)
	@$(CC) -M $(SWIGCFLAGS) $(CFLAGS) $(SRC)  > .depend

version.h: .svn/entries
	./configure

tags: $(SRC) $(HDRS)
	@$(CTAGS) $(SRC) $(HDRS)

cvs: 
	cvs update

debug: 
	@echo OBJ=$(OBJS)
	@echo SRC=$(SRC)
