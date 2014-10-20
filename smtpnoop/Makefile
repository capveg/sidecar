TARGET=smtpnoop.pl
include ../Make.include
CFLAGS+=-I/usr/include/pcap
CFLAGS+=-I..


# nothing to do for all
all: 



install: all
	mkdir -p $(PREFIX)
	cp $(TARGET) $(PREFIX)/$(TARGET)
	chmod 755 $(PREFIX)/$(TARGET)
	cp  smtplist perl-Event-1.06-1.1.fc2.rf.i386.rpm $(PREFIX)/
install_clean:
	rm -f $(PREFIX)/$(TARGET)
	@rmdir --ignore-fail-on-non-empty $(PREFIX)

debug: 
	@echo OBJ=$(OBJS)
	@echo SRC=$(SRC)
clean:
