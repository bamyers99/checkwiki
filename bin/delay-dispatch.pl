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

use lib '/data/project/checkwiki/bin';
use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use feature 'unicode_strings';
use POSIX qw(strftime);
use CheckwikiK8Api;

my @ProjectList = qw(enwiki dewiki eswiki frwiki arwiki cswiki plwiki bnwiki nlwiki nowiki cawiki hewiki ruwiki itwiki ptwiki);

my $cur_date = strftime( '%F', gmtime() );

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

my $sth = $dbh->prepare('SELECT last_update FROM cw_overview WHERE project = ?;')
  or die "Can not prepare statement: $DBI::errstr\n";

foreach my $project (@ProjectList) {

    $sth->execute( $project )
      or die "Cannot execute: $sth->errstr\n";

    my $last_update;
    $sth->bind_col( 1, \$last_update );
    
    $sth->fetchrow_arrayref;
    
    $last_update = substr( $last_update, 0, 10 );

	if ( $last_update lt $cur_date ) {
		queueUp( $project );
	}
}

$sth->finish();

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
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $project ) = @_;
    
    my $yaml = CheckwikiK8Api::build_yaml('cw-delay-' . $project, "/data/project/checkwiki/bin/delaywrapper.sh \"$project\"",
    	'512Mi', '250m');
    	
    my $response = CheckwikiK8Api::send_yaml($yaml);
        
    print '--project=' . $project . "\n";
    
    if ($response->code < 200 || $response->code >= 300) {print 'dispatch failed ' . $response->code . ' ' . $response->content};

    return();
}