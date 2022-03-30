#! /usr/bin/env perl

###########################################################################
##
##          FILE: checkwiki-delay_dispatch
##
##         USAGE: ./checkwiki-delay_dispatch
##
##   DESCRIPTION: Runs from WMFLabs crontab.
##                Processes articles gathered from live_scan.pl.
##
##        AUTHOR: Bryan White
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;

my @ProjectList = qw(enwiki dewiki eswiki frwiki arwiki cswiki plwiki bnwiki);

foreach my $project (@ProjectList) {

    system(
        'jsub',
        '-j',             'y',
#        '-l',             'release=trusty',
        '-mem',           '3048m',
        '-release',		  'buster',
        '-N',             $project . '-delay',
        '-o',             '/data/project/checkwiki/var/log',
        '-once',          '/data/project/checkwiki/bin/checkwiki.pl',
        '--config',       '/data/project/checkwiki/checkwiki.cfg',
        '--load',         'delay',
        '--project',      $project
    );
}