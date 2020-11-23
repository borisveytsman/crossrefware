#!/usr/bin/env perl

=pod

=head1 NAME

ltx2crossrefxml.pl - create XML files for submitting to crossref.org

=head1 SYNOPSIS

ltx2crossrefxml [B<-c> I<config_file>]  [B<-o> I<output_file>] I<latex_file1> I<latex_file2> ...

=head1 OPTIONS

=over 4

=item B<-c> I<config_file>

Configuration file.  If this file is absent, defaults are used.
See below for its format.

=item B<-o> I<output_file>

Output file.  If this option is not used, the XML is output to stdout.

=back

The usual C<--help> and C<--version> options are also supported.

=head1 DESCRIPTION

For each given I<latex_file>, this script reads C<.rpi> and (if it
exists) C<.bbl> files, representing bibliographic information, and
outputs corresponding XML that can be uploaded to Crossref
(L<https://crossref.org>).

These C<.rpi> files are output by the C<resphilosophica> package
(L<https://ctan.org/pkg/resphilosophica>). They can also be created by
hand or by whatever other method you implement; they describe each
reference in the bibliography. An example is below.

The processing of the reference list is at present rather limited: only
so-called unstructured references are produced for Crossref.

This script just writes an XML file. It's up to you to actually do the
uploading to Crossref.

=head1 CONFIGURATION FILE FORMAT

The configuration file is mostly self-explanatory: it has comments
(starting with C<#>) and assignments in the form

   $field = value ;

The idea is to specify the user-specific and journal-specific values
needed for the Crossref upload.

=head1 RPI FILE FORMAT

Here's the C<.rpi> file created from the C<rpsample.tex> example in the
resphilosophica package (all the data is fake, of course):

  \relax 
  \articleentry{Boris Veytsman\and A. U. Th{\o }r\and C. O. R\"espondent}{A Sample Paper:\\ \emph  {A Template}}{1}{1}
  %authors=Boris Veytsman\and A. U. Th{\o }r\and C. O. R\"espondent
  %title=A Sample Paper:\\ \emph  {A Template}
  %year=2012
  %volume=90
  %issue=1--2
  %paper=2
  %startpage=1
  %endpage=1
  %doi=10.11612/resphil.A31245
  %paperUrl=http://borisv.lk.net/paper12

For more details on processing, see the code.

=head1 EXAMPLES

  ltx2crossrefxml.pl ../paper1/paper1.tex ../paper2/paper2.tex -o result.xml

  ltx2crossrefxml.pl -c myconfig.cnf paper.tex -o paper.xml

=head1 AUTHOR

Boris Veytsman L<https://github.com/borisveytsman/crossrefware>

=head1 COPYRIGHT AND LICENSE

Copyright 2012-2020 Boris Veytsman

This is free software.  You may redistribute copies of it under the
terms of the GNU General Public License
L<http://www.gnu.org/licenses/gpl.html>.  There is NO WARRANTY, to the
extent permitted by law.

=cut

 use strict;
 use warnings;

 BEGIN {
     # find files relative to our installed location within TeX Live
     chomp(my $TLMaster = `kpsewhich -var-value=SELFAUTOPARENT`); # TL root
     if (length($TLMaster)) {
	 unshift @INC, "$TLMaster/texmf-dist/scripts/bibtexperllibs";
     }
     unshift @INC, "."; # since the config file is probably in the cwd
 }
 use POSIX qw(strftime);
 use BibTeX::Parser::Author;
 use LaTeX::ToUnicode qw (convert);
 use File::Basename;
 use File::Spec;
 my $USAGE = <<END;
Usage: $0 [-c config] [-o output] ltxfile1 ltxfile2 ...

Convert .rpi and (if it exists) .bbl files to xml, for submitting to
crossref.org. The .rpi files are output by the resphilosophica LaTeX
package, or can be created by hand.

Development sources, bug tracker: https://github.com/borisveytsman/crossrefware
Releases: https://ctan.org/pkg/crossrefware
END

 my $VERSION = <<END;
ltx2crossrefxml (crossrefware) 2.3
This is free software: you are free to change and redistribute it, under
the terms of the GNU General Public License
http://www.gnu.org/licenses/gpl.html (any version).
There is NO WARRANTY, to the extent permitted by law.

Written by Boris Veytsman.
END
 use Getopt::Long;
 my %opts;

 GetOptions(
   "config|c=s" => \($opts{c}),
   "output|o=s" => \($opts{o}),
   "version|V"  => \($opts{V}),
   "help|?"     => \($opts{h})) || pod2usage(1);

 if ($opts{h}) { print $USAGE; exit 0; } 
 if ($opts{V}) { print $VERSION; exit 0; } 

 use utf8;
 binmode(STDOUT, ":utf8");

 ################################################################
 # Defaults and parameters
 ################################################################

 *OUT=*STDOUT;
 
 if (defined($opts{o})) {
     open (OUT, ">$opts{o}") or die "open($opts{o}) for writing failed: $!\n";
     binmode(OUT, ":utf8")
 }


 our $depositorName='DEPOSITOR_NAME';
 our $depositorEmail='DEPOSITOR_EMAIL';
 our $registrant='REGISTRANT';
 our $fullTitle = "FULL TITLE";
 our $abbrevTitle = "ABBR. TTL.";
 our $issn = "1234-5678";
 our $coden = "CODEN";
 our $batchId="ltx2crossref$$";
 our $timestamp=strftime("%Y%m%d%H%M%S", gmtime);


 if ($opts{c}) {
     if (-r $opts{c}) {
	 require $opts{c};
     } else {
	 die "Cannot read config file $opts{c}. Goodbye.";
     }
 }



 PrintHead();

 # 
 # The hash %papers.  Keys year->vol->issue->number
 #
 my %papers;

 foreach my $file (@ARGV) {
     AddPaper($file);
 }

 foreach my $year (keys %papers) {
     foreach my $volume (keys %{$papers{$year}}) {
	 foreach my $issue (keys %{$papers{$year}->{$volume}}) {
	     PrintIssueHead($year, $volume, $issue);
	     my $paperList = $papers{$year}->{$volume}->{$issue};
	     foreach my $paper (@{$paperList}) {
		 PrintPaper($paper);
	     }
	 }
     }

 }

 PrintTail();

 exit(0);


#####################################################
#  Printing the head and the tail
#####################################################

sub PrintHead {

    # do not output the <coden> or <abbrev_title> if the journal doesn't
    # have them.
    my $indent = "        ";
    my $coden_out = $coden ne "CODEN" ? "\n$indent<coden>$coden</coden>" : "";
    my $abbrev_title_out = $abbrevTitle ne "ABBR. TTL."
        ? "\n$indent<abbrev_title>$abbrevTitle</abbrev_title>"
        : "";

    print OUT <<END;
<doi_batch xmlns="http://www.crossref.org/schema/4.4.2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="4.4.2" xsi:schemaLocation="http://www.crossref.org/schema/4.4.2 http://www.crossref.org/schema/deposit/crossref4.4.2.xsd">
  <head>
    <doi_batch_id>$batchId</doi_batch_id>
    <timestamp>$timestamp</timestamp>
    <depositor>
      <name>$depositorName</name>
      <email_address>$depositorEmail</email_address>
    </depositor>
    <registrant>$registrant</registrant>
  </head>
  <body>
    <journal>
      <journal_metadata language="en">
        <full_title>$fullTitle</full_title>$abbrev_title_out
	<issn>$issn</issn>$coden_out	
      </journal_metadata>
END

}

sub PrintTail {
    print OUT <<END;
    </journal>
  </body>
</doi_batch>
END

return;
}


#######################################################
#  Adding one paper
#######################################################

sub AddPaper {
    my $file = shift;
    my ($name,$path,$suffix) = fileparse($file, '\.[^\.]*$');
    my $rpifile = File::Spec->catfile($path, "$name.rpi");
    open (RPI, $rpifile) or die 
     "Cannot find $rpifile.  Did you process $file?\n";
    my %data;
    while (<RPI>) {
	chomp;
        if (/^%([^=]*)\s*=\s*(.*)\s*$/) {
           $data{$1}=$2;
        }
    }
    close RPI;
    my @bibliography;
    foreach my $bibfile ($file, File::Spec->catfile($path, "$name.bbl")) {
         @bibliography = (@bibliography, 
          AddBibliography($bibfile));
    }
    $data{'bibliography'}=\@bibliography;
    push @{$papers{$data{year}}->{$data{volume}}->{$data{issue}}}, \%data;
}

############################################################## 
# Reading a list of papers and adding  it to the
# bibliography
##############################################################

sub AddBibliography {
    my $bibfile = shift;
    open (BIB, $bibfile) or return;
    my $insidebibliography = 0;
    my $currpaper="";
    my @result;
    my $key;
    while (<BIB>) {
	chomp;
	if (/^\s*\\bibitem(?:\[.*\])?+\{(.+)\}/) {
	    if ($insidebibliography) {
		if ($currpaper) {
		    my %paperhash;
		    $paperhash{$key}=$currpaper;
		    push @result, \%paperhash;
		}
	    }
	    $key = $1;
	    $currpaper="";
	    $insidebibliography=1;
	    next;
	}
	if (/^\s*\\end\{thebibliography\}/) {
	    if ($currpaper) {
		    my %paperhash;
		    $paperhash{$key}=$currpaper;
		    push @result, \%paperhash;
	    }
	    $currpaper="";
	    $insidebibliography=0;
	    next;
	}
	if ($insidebibliography) {
	    $currpaper .= " $_";
	}
    }
    close BIB;
    return @result;
}

#################################################################
#  Printing information about one issue
#################################################################

sub PrintIssueHead {
    my ($year, $volume, $issue) = @_;
    print OUT <<END;
      <journal_issue>
        <publication_date media_type="print">
          <year>$year</year>
        </publication_date>
        <journal_volume>
          <volume>$volume</volume>
        </journal_volume>
        <issue>$issue</issue>
      </journal_issue>
END
}

###############################################################
# Printing information about one paper
###############################################################
sub PrintPaper {
    my $paper = shift;
    my $title=convert($paper->{title});
    my $url=GetURL($paper);
    print OUT <<END;
      <journal_article publication_type="full_text">
        <titles>
           <title>
             $title
           </title>
        </titles>
        <contributors>
END
my @authors = split /\s*\\and\s*/, $paper->{authors};
    my $seq='first';
    foreach my $author (@authors) {
	print OUT <<END;
          <person_name sequence="$seq" contributor_role="author">
END
$seq='additional';
	PrintAuthor($author);
	print OUT <<END;
          </person_name>
END

    }

    print OUT <<END;
        </contributors>
        <publication_date media_type="print">
           <year>$paper->{year}</year>
        </publication_date>
        <pages>
           <first_page>$paper->{startpage}</first_page>
           <last_page>$paper->{endpage}</last_page>
        </pages>
        <doi_data>
          <doi>$paper->{doi}</doi>
          <timestamp>$timestamp</timestamp>
	  <resource>$url</resource>
        </doi_data>
END

if (scalar(@{$paper->{bibliography}})) {
    print OUT <<END;
        <citation_list>
END
    foreach my $citation (@{$paper->{bibliography}}) {
	PrintCitation($citation);
    }
    print OUT <<END;
        </citation_list>
END
}

    print OUT <<END;
      </journal_article>
END


}


###############################################################
#  Sanitization of a text string
###############################################################
sub SanitizeText {
    my $string = shift;
    $string = convert($string);
    $string =~ s/\\newblock//g;
    $string =~ s/\\bgroup//g;
    $string =~ s/\\egroup//g;
    $string =~ s/\\scshape//g;
    $string =~ s/\\urlprefix//g;
    $string =~ s/\\emph//g;
    $string =~ s/\\textbf//g;
    $string =~ s/\\enquote//g;
    $string =~ s/\\url/URL: /g;
    $string =~ s/\\doi/DOI: /g;
    $string =~ s/\\\\/ /g;
    $string =~ s/\$//g;
    $string =~ s/\\checkcomma/,/g;
    $string =~ s/~/ /g;
    $string =~ s/[\{\}]//g;
    return $string;
}

################################################################
# Printing one author
################################################################
sub PrintAuthor {
    my $author=shift;

    my $person=new BibTeX::Parser::Author ($author);

    if ($person->first) {
	my $line = $person->first;
	$line = SanitizeText($line);
	print OUT <<END;
            <given_name>$line</given_name>
END

    }

    if ($person->last) {
	my $line = SanitizeText($person->last);
	if ($person->von) {
	    $line = SanitizeText($person->von)." $line";
	}
	print OUT <<END;
            <surname>$line</surname>
END

    }

    if ($person->jr) {
	my $line = SanitizeText($person->jr);
	print OUT <<END;
            <suffix>$line</suffix>
END

    }

}

#############################################################
#  Printing citations
#############################################################
sub PrintCitation {
    my $paperhash=shift;
    foreach my $key (keys (%{$paperhash})) {
	my $citation=$paperhash->{$key};
	$citation=SanitizeText($citation);

	print OUT <<END;
          <citation key="$key">
             <unstructured_citation>
               $citation
             </unstructured_citation>
          </citation>
END
}

}

##############################################################
#  Calculating URL
##############################################################

sub GetURL {
    my $paper = shift;

    my $result;
    if ($paper->{paperUrl}) {
	$result= $paper->{paperUrl}
    } else {
	my $doi=$paper->{doi};
	$result= 'http://www.pdcnet.org/oom/service?url_ver=Z39.88-2004&rft_val_fmt=&rft.imuse_synonym=resphilosophica&rft.DOI='.$doi.'&svc_id=info:www.pdcnet.org/collection';
    }
    $result =~ s/&/&#38;/g;
    return $result;
}
