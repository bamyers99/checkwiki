#!/usr/bin/env perl
###########################################################################
##
##         FILE: checkarticle.pl
##
##
##  DESCRIPTION: Retrieves dumps lists from Wikipedia, scans the articles
##               and then uploads and updated lists
##
##       AUTHOR: Bgwhite
##      VERSION: 2016/12/27
##
###########################################################################

use strict;
use warnings;
use lib
'/data/project/checkwiki/perl5/perlbrew/perls/perl-5.24.0/lib/site_perl/5.24.0/';
use CGI::Lite;

###########################################################################

my @myarray;
my $article;
my $project;

my $cgi  = CGI::Lite->new();
my $data = $cgi->parse_form_data;

$article = $data->{article};
$project = $data->{project};

$project =~ s/[[:^lower:]]//g;

$article =~ s/%20/ /g;
$article =~ s/[+%?#<>|[{}\]\n\r\t]//g;
$article =~ tr/_/ /;

###########################################################################
## MAIN ROUTINE
###########################################################################

if ( $article ne q{''} ) {
    @myarray =
`/usr/bin/perl /data/project/checkwiki/bin/checkwiki.pl.new --load article  --article "$article" -c /data/project/checkwiki/checkwiki.cfg --project $project`;
}

print "Content Type: text/html; charset=UTF-8\n\n";

if ( defined( $myarray[0] ) ) {
    foreach my $error (@myarray) {
        print {*STDOUT} $error;
    }
}
else { print {*STDOUT} "None\n"; }