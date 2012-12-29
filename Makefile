SCRIPTS = \
	ltx2crossrefxml.pl

MAN1 = ${SCRIPTS:%.pl=%.1}

PDF = crossrefware.pdf

all:  ${MAN1} ${PDF}
	chmod a+x ${SCRIPTS}



%.1: %.pl
	pod2man -c "CROSSREF LIBRARY" -n $* -s 1 -r "" $< > $@




clean:
	$(RM) *.aux *.toc *.log *.tex *.idx *.ilg *.ind *.out

distclean: clean
	$(RM) *.pdf *.1 *.3


%.pdf: %.tex
	pdflatex $*
	makeindex $*
	pdflatex $*


crossrefware.tex: ${SCRIPTS} head.ltx
	pod2latex -modify -full -prefile head.ltx -out $@ $<
