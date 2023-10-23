#! /usr/bin/env perl

###########################################################################
##
##          FILE: dump_dispatcherbig.pl
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg
##
##   DESCRIPTION: Dispatches a dump process for big wikis
##
##        AUTHOR: Bryan White/Bamyers99
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;

use lib '/data/project/checkwiki/bin';
use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use feature 'unicode_strings';
use CheckwikiK8Api;

binmode( STDOUT, ':encoding(UTF-8)' );
my $project;

##########################################################################
## MAIN PROGRAM
##########################################################################

    if (!@ARGV) {
    	die( "Usage: dump-dispatchbig.pl <projectname>\n" );
    }
    
    $project = $ARGV[0];
    
    my ( $latestDumpDate, $latestDumpFilename ) = FindLatestDump();
          
    queueUp( $latestDumpDate, $latestDumpFilename );

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub FindLatestDump {

    # the 2 is in the file search to weed out the 'latest' directory which sorts last
    my @Filenames =
      </public/dumps/public/$project/2*/$project-*-pages-articles.xml.bz2>;
    if ( !@Filenames ) {
        return undef;
    }

    if ( $Filenames[-1] !~
m!/public/dumps/public/\Q$project\E/((\d{4})(\d{2})(\d{2}))*/\Q$project\E-\1-pages-articles.xml.bz2!
      )
    {
        die( 'Could not parse filename: ' . $Filenames[-1] . "\n" );
    }

    return ( $2 . q{-} . $3 . q{-} . $4, $Filenames[-1] );
}

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $date, $file ) = @_;
    
    # dual thread dump scans to allow other jobs to have resources
    my $jobname = 'cw-dumpscan1'
     
    my $yaml = CheckwikiK8Api::build_yaml($jobname, "/data/project/checkwiki/bin/dumpwrapper.sh dumpbig \"$project\" \"$file\"",
    	'2Gi', '250m');
    	
    my $response = CheckwikiK8Api::send_yaml($yaml);
    
    print '--project=' . $project . ' --dumpfile=' . $file . "\n";
    
    if ($response->code < 200 || $response->code >= 300) {print 'dispatch failed ' . $response->code . ' ' . $response->content};

    return();
}