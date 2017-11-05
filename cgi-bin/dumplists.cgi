#!/usr/bin/env perl
###########################################################################
##
##         FILE: update_dumplists.pl
##
##        USAGE: ./update_dumplists.pl --error
##
##  DESCRIPTION: Retrieves dumps lists from Wikipedia, scans the articles
##               and then uploads and updated lists
##
##       AUTHOR: Bgwhite
##      VERSION: 2014/02/27
##
###########################################################################

use strict;
use warnings;
use utf8;
use IPC::Open3;
use CGI qw(-utf8 :standard);

use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

###########################################################################

our @myarray;
our $Error_output;
our $Error_number;
our $TMPDIR  = "/data/project/checkwiki/var/tmp/";
our $bot = MediaWiki::Bot->new(
    {
        assert   => 'bot',
        protocol => 'http',
        host     => 'en.wikipedia.org',
    }
);


$Error_output = param('output');
$Error_number = param('error');

if ( $Error_number < 1 and $Error_number > 113 ) {
    print "No error number given\n\n" ;
    die "usage: program --error [NUMBER or all]\n";
}

###########################################################################
## MAIN ROUTINE
###########################################################################

print header(-charset=>'UTF-8');
print start_html('Simple Script');
get_errors();
parse_errors();
 
print "<pre><p>\n";
foreach (@myarray) {
    $_ =~ /\t([^\t]*)\t([^\t]*)\t(.*)$/;
    if ( $Error_number eq $1 ) {
        if ( $Error_output eq "detail" ) {
            my $detail = $3;
            my $title = $2;
            $detail =~ s/</&lt;/g;
            printf ("'%-60s'%-s'\n", $title, $detail );
        } elsif ( $Error_output eq "dump" ) {
            print '# [[' . $2 . "]]\n";
        } else {
            print  $2 . "\n";
        }
    }
}

print "</pre><p>\n";
print end_html;

###########################################################################
## GET ERRORS
###########################################################################

sub get_errors {

        my $error = $Error_number;
        my $page_title;
        my $filename = $TMPDIR . $error . '.in';

        if ( $error < 10 ) {
            $page_title = 'Wikipedia:CHECKWIKI/00' . $error . '_dump';
        }
        elsif ( $error < 100 and $error > 9) {
            $page_title = 'Wikipedia:CHECKWIKI/0' . $error . '_dump';
        }
        else {
            $page_title = 'Wikipedia:CHECKWIKI/' . $error . '_dump';
        }

        open( my $OUTFILE, ">:encoding(UTF-8)", $filename )
          or die 'Cannot open temp file ' . $filename . "\n";

        my $wikitext = $bot->get_text($page_title);

        my @lines = split( /\n/, $wikitext );
        foreach (@lines) {
            $_ =~ /# \[\[(.*?)\]\]/;
            print $OUTFILE $1 . "\n";
        }
        close($OUTFILE);

    return ();
}

##########################################################################
## PARSE ERRORS
##########################################################################

sub parse_errors {

    my $error    = $Error_number;
    my $filename = $error . '.txt';
    my $list     = $TMPDIR . $error . '.in';

    @myarray =
`/usr/bin/perl /data/project/checkwiki/bin/checkwiki.pl --load list  --listfile=$list -c /data/project/checkwiki/checkwiki.cfg --project=enwiki`;
    return ();
}