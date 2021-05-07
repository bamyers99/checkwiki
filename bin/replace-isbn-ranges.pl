#!/usr/bin/env perl

###########################################################################
##
##         FILE: replace-isbn-ranges.pl
##
##        USAGE: ./replace-isbn-ranges.pl
##
##  DESCRIPTION: retrieves current ISBN ranges and replaces perl/lib/perl5/Business/ISBN/RangeMessage.xml
##
##       AUTHOR: Bruce Myers
##      LICENCE: GPLv3
##      VERSION: 05/07/2021
##
###########################################################################

use strict;
use warnings;
use utf8;
use feature 'unicode_strings';
use LWP::UserAgent;

binmode( STDOUT, ":encoding(UTF-8)" );

##########################################################################
## MAIN PROGRAM
##########################################################################

my $url = 'https://www.isbn-international.org/export_rangemessage.xml';

my $response;

my $ua = LWP::UserAgent->new;
$response = $ua->get($url);

if ($response->code != 200) {
	print 'Error response = ' . $response->code;
	die;
}

my $content = $response->content;

my $outfile = '/data/project/checkwiki/perl/lib/perl5/Business/ISBN/RangeMessage.xml';

open my $fh, '>', $outfile or die;
binmode $fh;

print $fh $content;
close $fh;
