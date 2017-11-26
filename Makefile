SCRIPTS = \
	ltx2crossrefxml.pl \
	bibdoiadd.pl \
	bibzbladd.pl \
	bibmradd.pl \
	biburl2doi.pl \
	bbl2bib.pl

PACKAGE = crossrefware

MAN1 = ${SCRIPTS:%.pl=%.1}

PDF = crossrefware.pdf

all:  ${MAN1} ${PDF}
	chmod a+x ${SCRIPTS}



%.1: %.pl
	pod2man -c "CROSSREF LIBRARY" -n $* -s 1 -r "" $< > $@




clean:
	$(RM) *.aux *.toc *.log *.tex *.idx *.ilg *.ind *.out *.zip *.tgz \
	*~

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
	COPYFILE_DISABLE=1 tar -C .. -czvf ../$(PACKAGE).tgz --exclude '*~' --exclude '*.tgz' --exclude '*.zip'  --exclude CVS --exclude '.git*' $(PACKAGE); mv ../$(PACKAGE).tgz .
