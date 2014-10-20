FOO=bar

FACTS=abilene canet4 geant nlr
OBSERVED=alltrace-solver.adj tr-traces.adj rand-imc07.adj nlr-fix2-nolazygap=2-C=unknown-1.adj
DLV=$(patsubst %,%-facts.dlv,$(FACTS))
ADJ=$(subst .dlv,.adj,$(DLV))

DEFRINGED = $(subst .dlv,-defringed.adj,$(DLV))
CLEANED = $(subst .adj,-cleaned.adj,$(OBSERVED))


validate += $(foreach dataset,$(DEFRINGED),$(dataset)-solver-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-norrend-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-rocketfuel-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-imc07-out)

validate += $(foreach dataset,$(DEFRINGED),$(dataset)-solver-clean-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-norrend-clean-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-rocketfuel-clean-out)
validate += $(foreach dataset,$(DEFRINGED),$(dataset)-imc07-clean-out)



all: $(ADJ) $(DEFRINGED) $(CLEANED) $(validate) mapping-compare.data cluster-score.data
	grep MAP `ls *-out | sort` > mapping-compare.data
	perl -pi -e 's/ /\t/g; s/rocketfuel/rfuel/g' mapping-compare.data
	grep CLUSTERSCORE `ls *-out | sort` > cluster-score.data
	grep LINK-STAT `ls *-out | sort` > link-stats.data

configs.html:
	wget http://vn.grnoc.iu.edu/Abilene/configs/configs.html

show_interfaces.xml:
	wget http://vn.grnoc.iu.edu/xml/abilene/show_interfaces.xml
	touch $@

#$(out).dlv: ./parse_interfaces.rb show_interfaces.xml
# 	./parse_interfaces.rb > $@

%.adj: %.dlv
	PATH=$${PATH}:../scripts dlv2adj.pl -o $@ $<

%-cleaned.adj: %.adj
	@echo Cleaning $< \(noop\)
	#./validate.rb -clean $<
	cp $< $@
%-defringed.adj: %.adj
	@echo Defringing $<
	./validate.rb -defringe $<

# main solver out

%.adj-solver-out: %.adj alltrace-solver.adj
	./validate.rb -validate $+ > $@
	
%.adj-norrend-out: %.adj alltrace-norrend.adj
	./validate.rb -validate $+ > $@

%.adj-rocketfuel-out: %.adj tr-traces.adj
	./validate.rb -validate $+ > $@

%.adj-imc07-out: %.adj rand-imc07.adj
	./validate.rb -validate $+ > $@

# "cleaned" versions


%.adj-solver-clean-out: %.adj alltrace-solver-cleaned.adj
	./validate.rb -validate $+ > $@
%.adj-norrend-clean-out: %.adj alltrace-norrend-cleaned.adj
	./validate.rb -validate $+ > $@
%.adj-rocketfuel-clean-out: %.adj tr-traces-cleaned.adj
	./validate.rb -validate $+ > $@
%.adj-imc07-clean-out: %.adj alltrace-imc07-cleaned.adj
	./validate.rb -validate $+ > $@

debug:
	@echo $(ADJ) 
	@echo -------------------------
	@echo $(DEFRINGED)
	@echo -------------------------
	@echo $(validate)


#$(out).pdf: $(out).adj
#	PATH=$${PATH}:../scripts adjacency2map.sh -neato $(out).adj > $(out).dot

#$(out).prefixes: $(out).adj
#	adjacency2ips.sh $(out).adj > $(out).ips
#	cut -f1,2,3 -d. $(out).ips | sort | uniq -c | sort -n > $(out).prefixes

#diff-$(out): $(out).adj
#	adjacency2subset.pl $(prefixes) $(out).adj > plab-abilene-subset.adj
#	diffadj.pl $(out).adj plab-abilene-subset.adj > diff-$(out) || true

clean:
	rm -f $(ADJ) $(CLEANED) $(DEFRINGED) $(validate)
