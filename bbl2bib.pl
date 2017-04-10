#!/usr/bin/env perl

=pod

=head1 NAME

bbl2bib.pl - convert thebibliography environment to a bib file

=head1 SYNOPSIS

bibdoiadd [B<-c> I<config_file>]  [B<-o> I<output>] [-s I<search_order>] I<file>

=head1 OPTIONS

=over 4

=item B<-c> I<config_file>

Configuration file.  If this file is absent, some defaults are used.
See below for its format.


=item B<-o> I<output>

Output file.  If this option is not used, the name for the 
output file is formed by changing the extension to C<.bib>

=item B<-s> I<search_order>

The databases to search for the article or book.  A sequence of
letters C<m>, C<d> and C<z>, by default C<mzd>.  The letters
mean:

=over 4


=item B<m> 

MathSciNet, C<http://www.ams.org/mathscinet-mref>, the reference
database of MR numbers.

=item B<z> 

zbMATH, C<https://zbmath.org>, the reference database of Zbl numbers.

=item B<d> 

Crossref, C<http://www.crossref.org>, the reference database of DOI 
identifiers.

=back

Note that at present searches in the crossref database require an
account, so if you do not have one, you may want to use C<-s mz>
option to exclude Crossref from searches.  Note also that after the
item is found in any database, the search is stopped, so if you use
C<-s mzd> (the default), and the citation is found in MathSciNet,
neither zbMATH nor Crossref is searched for the citation.

=back

=head1 DESCRIPTION

The script tries to reconstruct a C<bib> file from the corresponding
C<thebibliography> environment.  One can argue that this operation is
akin to reconstructing a cow from the steak.  The way the script does
it is searching for the entry in the MR, ZBL and DOI databases, and
creating the corresponding BibTeX fields.

The script reads a TeX or Bbl file and extracts from it the
C<thebibliography> environment.  For each bibitem it creates a plain
text bibliography entry, and then consequitevly tries to match it in
the databases.  If it finds a match, it outputs the BibTeX entry and 
stops the further search.  

=head1 INPUT FILE

We assume some structure of the input file:

=over 4

=item 1.

The bibliography is contained between the lines

   \begin{thebibliography}...

and

   \end{thebibliography}

=item 2.

Each bibliography item starts from the line 

   \bibitem[...]{....}

=back


=head1 CONFIGURATION FILE 

The configuration file is mostly self-explanatory: it has comments
(starting with C<#>) and assginments in the form

   $field = value ;

At present you need this file only to search the Crossref database,
and therefore its format is the same as the configuration file for
L<bibdoiadd(1)> program. The parameters are C<$mode> for Crossref
(C<'free'> or C<'paid'>), C<$email> (for free users) and C<$username>
& C<$password> for paid members.


=head1 EXAMPLES

   bbl2bib -c bibdoiadd.cfg -o - file.tex > result.bib
   bbl2bib -c bibdoiadd.cfg -o result.bib file.bbl
   bbl2bib -c bibdoiadd.cfg file.tex

=head1 AUTHOR

Boris Veytsman

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2017  Boris Veytsman

This is free software.  You may redistribute copies of it under the
terms of the GNU General Public License
L<http://www.gnu.org/licenses/gpl.html>.  There is NO WARRANTY, to the
extent permitted by law.

=cut

use strict;
BEGIN {
    # find files relative to our installed location within TeX Live
    chomp(my $TLMaster = `kpsewhich -var-value=SELFAUTOPARENT`); # TL root
    if (length($TLMaster)) {
	unshift @INC, "$TLMaster/texmf-dist/scripts/bibtexperllibs";
    }
}
use IO::File;
use BibTeX::Parser;
use FileHandle;
use LaTeX::ToUnicode qw (convert);
use Getopt::Std;
use URI::Escape;
use LWP::Simple;

my $USAGE="USAGE: $0 [-c config] [-o output] [-s search_order] file\n";
my $VERSION = <<END;
bbl2bib v2.1
This is free software.  You may redistribute copies of it under the
terms of the GNU General Public License
http://www.gnu.org/licenses/gpl.html.  There is NO WARRANTY, to the
extent permitted by law.
$USAGE
END
our %opts;
getopts('c:o:s:hV',\%opts) or die $USAGE;

if ($opts{h} || $opts{V}){
    print $VERSION;
    exit 0;
}

################################################################
# Defaults and parameters
################################################################

my $inputfile = shift;

my $outputfile = $inputfile;

$outputfile =~ s/\.([^\.]*)$/.bib/;

if (exists $opts{o}) {
    $outputfile = $opts{o};
}

my $searchOrder = 'mzd';
if (exists $opts{s}) {
    $searchOrder=$opts{s};
}

$searchOrder =~ s/\s//g;

# For Crossref
our $mode='free';
our $email;
our $username;
our $password;

if ($opts{c}) {
    if (-r $opts{c}) {
	push @INC, ".";
	require $opts{c};
    } else {
	die "Cannot read options $opts{c}.  $USAGE";
    }
}


# Check the consistency

if ($searchOrder =~ /d/ && 
    $mode eq 'free' && !length($email)) {
    die "Crossref requires a registered e-mail for the free mode queries\n";
}

if ($searchOrder =~ /d/ && 
    $mode eq 'paid' && (!length($username) || !length($password))) {
    die 
	"Crossref requires a username and password for the paid mode queries\n";
}

my $input= IO::File->new($inputfile) or 
    die "Cannot find Bbl or TeX file $inputfile\n$USAGE\n";
my $output = IO::File->new("> $outputfile") or 
    die "Cannot write to $outputfile\n$USAGE\n";

my $userAgent = LWP::UserAgent->new;


# Bibitem is a hash with the entries 'key', 'text', 'mrnumber',
# 'arxiv', 'zbl'
my $bibitem;

while (<$input>) {
    if (!(/\\begin\{thebibliography\}/../\\end\{thebibliography\}/) ||
	/\\begin\{thebibliography\}/ || /\\end\{thebibliography\}/) {
	next;
    }
    if (/\\bibitem(\[[^\]]*\])?\{([^\}]*)\}/) {
	ProcessBibitem($bibitem);
	$bibitem = undef;
	$bibitem->{key}=$2;
	$bibitem->{text}="";
    }
    if (!/^\s*$/) {
	$bibitem -> {text} .= $_;
    }
}
ProcessBibitem($bibitem);


exit 0;

sub ProcessBibitem {
    my $bibitem = shift;
    my $key = $bibitem->{key};
    my $text=$bibitem->{text};
    if (!length($text) || $text =~ /^\s+$/s) {
	return;
    }
    my $printtext = $text;
    $printtext =~ s/^(.)/% $1/gm;
    print $output "$printtext";

    $text =~ s/\n/ /mg;
    $text =~ s/\\bibitem(\[[^\]]*\])?\{[^\}]*\}//;

    # Arxiv entry?
    if ($text =~ s/\\arxiv\{([^\}]+)\}\.?//) {
	$bibitem->{arxiv}=$1;
    }

    # Mr number exists?
    if ($text =~ s/\\mr\{([^\}]+)\}\.?//) {
	$bibitem->{mr}=$1;
    }

    # zbl  number exists?
    if ($text =~ s/\\zbl\{([^\}]+)\}\.?//) {
	$bibitem->{zbl}=$1;
    }

    # doi  number exists?
    if ($text =~ s/\\doi\{([^\}]+)\}\.?//) {
	$bibitem->{doi}=$1;
    }

    print $key, "\n";
    print $text, "\n";
    foreach my $dbletter (split (//, $searchOrder)) {
	if ($dbletter eq 'm') {
	    $bibitem->{bib} = SearchMref($bibitem);
	}
	if (ref($bibitem->{bib})) {
	    PrintBibitem($bibitem);
	    return;
	}
    }
}


sub SearchMref {
    my $bibitem = shift;
    my $mirror = "http://www.ams.org/mathscinet-mref";
    my $string=uri_escape_utf8($bibitem->{text});
    my $response = $userAgent->get("$mirror?ref=$string&dataType=bibtex") ->
	decoded_content();
    if ($response =~ /<pre>(.*)<\/pre>/s) {
	my $bib= $1;
	my $fh = new FileHandle;
	open $fh, "<", \$bib;
	my $parser = new BibTeX::Parser($fh);
	my $entry = $parser->next;
	if ($entry->parse_ok()) {
	    $entry->key($bibitem->{key});
	    return ($entry);
	}
    }
}

sub PrintBibitem {
    my $bibitem = shift;
    if (!ref($bibitem->{bib})) {
	return;
    }
    my $entry=$bibitem->{bib};
    if ($entry->field('mrnumber')) {
	my $mr=$entry->field('mrnumber');
	while (length($mr)<7) {
	    $mr = "0$mr";
	}
	$mr=$entry->field('mrnumber', $mr);
    }
    print $bibitem->{bib}->to_string(), "\n\n";
}

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

