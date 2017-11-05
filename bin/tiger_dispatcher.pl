#! /usr/bin/env perl

###########################################################################
##
##          FILE: single_dispatcher.pl 
##
##         USAGE: ./single_dispatch.pl
##
##   DESCRIPTION: Sends a checkwiki.pl job to the WMFLabs queue 
##
##        AUTHOR: Bryan White
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;
use utf8;

use DBI;

binmode( STDOUT, ':encoding(UTF-8)' );

##########################################################################
## MAIN PROGRAM
##########################################################################

my $language = 'enwiki';
my $dumpdate = '20170101';
my $filename = '/public/dumps/public/enwiki/' . $dumpdate . '/' . $language . '-' . $dumpdate . '-pages-articles.xml.bz2';

queueUp( $language, $filename );

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $lang, $file ) = @_;

    system(
        'jsub',
        '-mem', '2048m',
        '-N', 'dumpmuncher-' . $lang,
        '-once',
        '-j', 'y',
        '-l', 'release=trusty',
        '-o', '/data/project/checkwiki/var/log',
        '/data/project/checkwiki/bin/tiger.pl',
        '-c', '/data/project/checkwiki/checkwiki.cfg',
        '--project', $lang,
        '--tt',
        '--dumpfile', $file,
    );

    print "jsub\n";
    print "-mem, 512m\n";
    print '-N, dumpmuncher-' . $lang . "\n";
    print "-once\n";
    print "-j, y\n";
    print "-o, /data/project/checkwiki/var/log\n";
    print "/data/project/checkwiki/bin/checkwiki.pl\n";
    print "-c, /data/project/checkwiki/checkwiki.cfg\n";
    print '--project,' . $lang . "\n";
    print "--tt\n";
    print '--dumpfile,' . $file . "\n";
}