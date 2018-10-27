#!/usr/bin/env perl 

###########################################################################
##
##         FILE: convert-checkwiki.pl
##
##        USAGE: ./update_dumplists.pl --error --input --output
##
##  DESCRIPTION: Converts Checkwiki output into a list of articles.
##               If Output=list, plain list of articles is produced, else
##               numerical wiki-formated list is produced.
##
##       AUTHOR: Bgwhite
##      LICENSE: GPLv3
##      VERSION: 2014/06/25
##
###########################################################################

use strict;
use warnings;

use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

###########################################################################

our @errors;
my ( $Error_number, $Output, $Input );

GetOptions(
    'error=s'  => \$Error_number,
    'input=s'  => \$Input,
    'output=s' => \$Output,
);

if ( $Error_number eq 'all' ) {
    @errors =
      qw ( 1 2 3 4 5 6 7 8 9 10 13 14 15 16 17 19 20 22 23 24 25 26 28 29 32 34 36 37 38 39 40 42 43 44 45 46 47 48 49 52 54 55 57 58 60 62 63 64 65 65 66 69 71 74 75 76 78 80 83 84 85 86 87 88 89 90 91 93 94 );
}
else {
    @errors = ($Error_number);
}
if ( !defined($Input) ) {
    $Input = 'out';
}

###########################################################################
## MAIN ROUTINE
###########################################################################

foreach (@errors) {

    my $error    = $_;
    my $filename = $error . '.txt';

    open( my $outfile, ">:encoding(UTF-8)", $filename )
      or die 'Cannot open temp file ' . $filename . "\n";
    open( my $infile,  "<:encoding(UTF-8)", $Input )
      or die 'Cannot open temp file ' . $Input . "\n";

    while (<$infile>) {
        my $line = $_;

        if ( $line =~ /^\t\d/ ) {
            $line =~ /\t([^\t]*)\t([^\t]*)\t/;
            if ( $error eq $1 ) {
                if ( $Output eq 'list' ) {
                    print $outfile $2 . "\n";
                }
                else {
                    print $outfile '# [[' . $2 . "]]\n";
                }
            }
        }
    }

    close($outfile);
    close($infile);
}