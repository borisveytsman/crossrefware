#!/usr/bin/env perl

=pod

=head1 NAME

bibdoiadd.pl - add a DOI number to papers in a given bib file

=head1 SYNOPSIS

bibdoiadd [B<-c> I<config_file>]  [B<-o> I<output>] I<bib_file>

=head1 OPTIONS

=over 4

=item B<-c> I<config_file>

Configuration file.  If this file is absent, some defaults are used.
See below for its format.


=item B<-o> I<output>

Output file.  If this option is not used, the result is output to stdout.

=back

=head1 DESCRIPTION

The script reads a BibTeX file.  It checks whether the entries have
DOIs.  If now, tries to contact http://www.crossref.org to get the
corresponding DOI.  The result is a BibTeX file with the fields
C<doi=...> added.

=head1 CONFIGURATION FILE FORMAT

The configuration file is mostly self-explanatory: it has comments
(starting with C<#>) and assginments in the form

   $field = value ;

=head1 EXAMPLES

   bibdoiadd -c bibdoiadd.cfg citations.bib > result.bib
   bibdoiadd -c bibdoiadd.cfg citations.bib -o result.bib

=head1 AUTHOR

Boris Veytsman

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014  Boris Veytsman

This is free software.  You may redistribute copies of it under the
terms of the GNU General Public License
L<http://www.gnu.org/licenses/gpl.html>.  There is NO WARRANTY, to the
extent permitted by law.

=cut

 use strict;

 my $USAGE="USAGE: $0 [-c config] [-o output] file ...\n";
 use Getopt::Std;
 my %opts;
 getopts('c:o:',\%opts) or die $USAGE;

 ################################################################
 # Defaults and parameters
 ################################################################

 *OUT=*STDOUT;
 
 if (defined($opts{o})) {
     open (OUT, ">$opts{o}") or die "Cannot open file $opts{o} for writing\n";
 }

 if ($opts{c}) {
     if (-r $opts{c}) {
	 require $opts{c};
     } else {
	 die "Cannot read options $opts{c}.  $USAGE";
     }
 }

