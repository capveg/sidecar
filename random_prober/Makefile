# Stolen from nspring - capveg 01/07
srcdir=.
WGET=wget
uniqw=uniq
MASK=24

all: addresses.$(MASK).filtered
	./informed_probe.sru -genStopList addresses.$(MASK).filtered > addresses.$(MASK).filtered.out

addresses.$(MASK).filtered: addresses.$(MASK)
	cat addresses.$(MASK) | ./filter_blacklist.rb > addresses.$(MASK).filtered

addresses.$(MASK): ./grabDotOnes.rb origins.dat
	./grabDotOnes.rb $(MASK)

oix-full-snapshot-latest.dat.bz2:
	$(WGET)  http://archive.routeviews.org/oix-route-views/`date +%Y.%m`/oix-full-snapshot-latest.dat.bz2

origins.dat: oix-full-snapshot-latest.dat.bz2 $(srcdir)/show_origins.pl
	$(srcdir)/show_origins.pl $< |sort | $(uniqw) > $@
	test -s $@   # ensure that it has nonzero size before declaring victory

clean:
	rm -f addresses.$(MASK) addresses.$(MASK).randomized oix-full-snapshot-latest.dat.bz2 origins.dat
