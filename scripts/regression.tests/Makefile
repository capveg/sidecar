# regression testing

GOODFILES=$(patsubst %.test, %.test.dlv, $(wildcard *.test))

all: $(GOODFILES)
	../dlv-testing.sh

clean:
	rm -f *.log *.out *.diff *.model *.adj *.dot *.dlv *.pdf *.ps

