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

binmode( STDOUT, ':encoding(UTF-8)' );

##########################################################################
## MAIN PROGRAM
##########################################################################

my $language = 'asqwiki';
my $dumpdate = '20151201';
my $filename =
    '/data/project/checkwiki/dumps/'
  . $language . q{-}
  . $dumpdate
  . '-pages-articles.xml.bz2';

queueUp( $language, $filename );

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $lang, $file ) = @_;

    system(
        'jsub',
        '-j',         'y',
        '-l',         'release=trusty',
        '-mem',       '3072m',
        '-N',         $lang . '-munch',
        '-o',         '/data/project/checkwiki/var/log',
        '-once',      '/data/project/checkwiki/bin/checkwiki.pl',
        '--config',   '/data/project/checkwiki/checkwiki.cfg',
        '--load',     'dump',
        '--project',  $lang,
        '--dumpfile', $file,
    );

    print "jsub\n";
    print "-j, y\n";
    print "-l, release=trusty,\n";
    print "-mem, 7072m\n";
    print '-N,' . $lang . "-munch\n";
    print "-o, /data/project/checkwiki/var/log\n";
    print "-once, /data/project/checkwiki/bin/checkwiki.pl\n";
    print "--config, /data/project/checkwiki/checkwiki.cfg\n";
    print "--load, dump\n";
    print '--project,' . $lang . "\n";
    print '--dumpfile,' . $file . "\n";

    return ();
}