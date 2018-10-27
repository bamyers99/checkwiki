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
use IPC::Open3;
use Encode;
use CGI qw(:standard);

use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ":encoding(UTF-8)" );

###########################################################################

our $TMPDIR  = "/data/project/checkwiki/var/";
our $bot = MediaWiki::Bot->new(
    {
        assert   => 'bot',
        protocol => 'http',
        host     => 'en.wikipedia.org',
    }
);

my ( $Error_number );

###########################################################################

$Error_number = param('error');

if ( $Error_number < 1 && $Error_number > 102 ) {
    print "No error number given\n\n" ;
    die "usage: program --error [NUMBER or all]\n";
}

###########################################################################
## MAIN ROUTINE
###########################################################################

get_errors();
parse_errors();

print "All done\n";

## GET ERRORS
###########################################################################

sub get_errors {

        my $error = $Error_number;
        my $page_title;
        my $filename = $TMPDIR . $error . '.in';

        if ( $error < 10 ) {
            $page_title = 'Wikipedia:CHECKWIKI/00' . $error . '_dump';
        }
        else {
            $page_title = 'Wikipedia:CHECKWIKI/0' . $error . '_dump';
        }

        print 'Retrieving information from ' . $page_title . "\n";

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

        my @myarray =
`/usr/bin/perl /data/project/checkwiki/bin/checkwiki.pl --load list  --listfile=$list -c /data/project/checkwiki/checkwiki.cfg --project=enwiki`;


        foreach (@myarray) {
            $_ = decode_utf8($_);
            $_ =~ /\t([^\t]*)\t([^\t]*)\t/;
            if ( $error eq $1 ) {
                print '# [[' . $2 . "]]\n";
            }
        } 
    return ();
}