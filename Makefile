SCRIPTS = \
	ltx2crossrefxml.pl \
	bibdoiadd.pl \
	bibzbladd.pl


MAN1 = ${SCRIPTS:%.pl=%.1}

PDF = crossrefware.pdf

all:  ${MAN1} ${PDF}
	chmod a+x ${SCRIPTS}



%.1: %.pl
	pod2man -c "CROSSREF LIBRARY" -n $* -s 1 -r "" $< > $@




clean:
	$(RM) *.aux *.toc *.log *.tex *.idx *.ilg *.ind *.out *.zip *.tgz

distclean: clean
	$(RM) *.pdf *.1 *.3


%.pdf: %.tex
	pdflatex $*
	makeindex $*
	pdflatex $*

crossrefware.tex:  head.ltx

crossrefware.tex: ${SCRIPTS} 
	pod2latex -modify -full -prefile head.ltx -out $@ $+

archive: all clean
	cd ..; tar -czvf crossrefware.tgz crossref --exclude CVS