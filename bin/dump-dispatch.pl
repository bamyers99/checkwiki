#! /usr/bin/env perl

###########################################################################
##
##          FILE: dump_dispatcher.pl
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg
##
##   DESCRIPTION: Checks for new dump files from all languages.
##                If new dump file is found, send checkwiki.pl proccess
##                to the queue.
##
##        AUTHOR: Bryan White
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

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Projects;
my @Last_Dump;
my @ProjectIds;

#Database configuration
my ( $DbName, $DbServer, $DbUsername, $DbPassword, $config_name, $dbh );

GetOptions(
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'config|c=s'   => \$config_name
);

if ( defined $config_name ) {
    open( my $file, '<:encoding(UTF-8)', $config_name )
      or die 'Could not open file ' . $config_name . "\n";
    while ( my $line = <$file> ) {
        chomp($line);
        my @words = ( split / /, $line );
        $DbName     = $words[1] if ( $words[0] =~ /--database/ );
        $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
        $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
        $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
    }
    close($file)
      or die 'Could not close file ' . $config_name . "\n";
}
else {
    die("No config file entered, for example: -c checkwiki.cfg\n");
}

open_db();
get_projects();

my $count        = 0;
my $project;

foreach (@Projects) {

    $project = $_;
    # Skip dailies
    if (    $project ne 'enwiki'
        and $project ne 'dewiki'
        and $project ne 'eswiki'
        and $project ne 'frwiki'
        and $project ne 'arwiki'
        and $project ne 'cswiki'
        and $project ne 'plwiki'
        and $project ne 'bnwiki'
        and $project ne 'nlwiki'
        and $project ne 'nowiki'
        and $project ne 'cawiki'
        and $project ne 'hewiki'
        and $project ne 'itwiki'
        and $project ne 'ptwiki'
        and $project ne 'ukwiki'
        and $project ne 'ruwiki' )
    {
        my $lastDump = $Last_Dump[$count];
        my $projectid = $ProjectIds[$count];
        my ( $latestDumpDate, $latestDumpFilename ) = FindLatestDump();
          
        if ( !defined($lastDump) || $lastDump ne $latestDumpDate ) {
            queueUp( $latestDumpDate, $latestDumpFilename, $projectid );
        }
    }
    $count++;

}

close_db();

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8 => 1,
        }
    ) or die( 'Could not connect to database: ' . DBI::errstr() . "\n" );

	$dbh->do('SET NAMES utf8mb4')
	   or die($dbh->errstr);

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {

    my $sth = $dbh->prepare('SELECT Project, Last_Dump, id FROM cw_overview;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    my ( $project_sql, $last_dump_sql, $projectid_sql );
    $sth->bind_col( 1, \$project_sql );
    $sth->bind_col( 2, \$last_dump_sql );
    $sth->bind_col( 3, \$projectid_sql );

    while ( $sth->fetchrow_arrayref ) {
        push( @Projects,  $project_sql );
        push( @Last_Dump, $last_dump_sql );
        push( @ProjectIds, $projectid_sql );
    }

    return ();
}

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
    my ( $date, $file, $projectid ) = @_;
    
    my $jobname = 'cw-dumpscan';
     
    my $yaml = CheckwikiK8Api::build_yaml($jobname, "/data/project/checkwiki/bin/dumpwrapper.sh \"$project\" \"$file\"",
    	'2Gi', '1250m');
    	
    my $response = CheckwikiK8Api::send_yaml($yaml);
    
    print '--project=' . $project . ' --dumpfile=' . $file . "\n";
    
    if ($response->code < 200 || $response->code >= 300) {print 'dispatch failed ' . $response->code . ' ' . $response->content};

    return();
}