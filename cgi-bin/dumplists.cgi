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
##      VERSION: 2017/01/07
##
###########################################################################

use strict;
use warnings;
use lib
'/data/project/checkwiki/perl5/perlbrew/perls/perl-5.24.0/lib/site_perl/5.24.0/';

use CGI::Lite;
use CGI::Carp qw(fatalsToBrowser);

use MediaWiki::API;
use MediaWiki::Bot;

###########################################################################

my @myarray;
my $Error_output;
my $Error_number;
my $TMPDIR = '/data/project/checkwiki/var/tmp/';
my $bot    = MediaWiki::Bot->new(
    {
        assert   => 'bot',
        protocol => 'https',
        host     => 'en.wikipedia.org',
        operator => 'CheckWiki',
    }
);

my $cgi  = CGI::Lite->new();
my $data = $cgi->parse_form_data;

$Error_output = $data->{output};
$Error_number = $data->{error};

if ( $Error_number < 1 and $Error_number > 113 ) {
    print "No error number given\n\n";
    die "usage: program --error [NUMBER or all]\n";
}

###########################################################################
## MAIN ROUTINE
###########################################################################

print "Content-type: text/html\n\n";
print "<!DOCTYPE html>\n";
print qq{<head>\n<meta charset=\"UTF-8\" />\n};
print "<title>Check Wikipedia Dumplist</title>\n</head>\n<body>\n";
print "<pre><p>\n";

get_errors();
parse_errors();

foreach my $line (@myarray) {
    $line =~ /\t([^\t]*)\t([^\t]*)\t(.*)$/;
    if ( $Error_number eq $1 ) {
        if ( $Error_output eq 'detail' ) {
            my $detail = $3;
            my $title  = $2;
            $detail =~ s/</&lt;/g;
            printf {*STDOUT} ( "'%-60s'%-s'\n", $title, $detail );
        }
        elsif ( $Error_output eq 'dump' ) {
            print {*STDOUT} '# [[' . $2 . "]]\n";
        }
        else {
            print {*STDOUT} $2 . "\n";
        }
    }
}

print "</pre>\n</body>\n</html>";

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
    elsif ( $error < 100 and $error > 9 ) {
        $page_title = 'Wikipedia:CHECKWIKI/0' . $error . '_dump';
    }
    else {
        $page_title = 'Wikipedia:CHECKWIKI/' . $error . '_dump';
    }

    my $wikitext = $bot->get_text($page_title);
    my @lines = split( /\n/, $wikitext );

    open( my $OUTFILE, '>:encoding(UTF-8)', $filename )
      or die "Cannot open temp file: $filename\n";

    foreach my $line (@lines) {
        $line =~ /# \[\[(.*?)\]\]/;
        print {$OUTFILE} $1 . "\n";
    }
    close($OUTFILE)
      or die "Cannot open temp file: $filename\n";

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